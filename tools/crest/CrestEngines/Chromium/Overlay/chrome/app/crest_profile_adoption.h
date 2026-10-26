// Copyright 2025 The Crest Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_APP_CREST_PROFILE_ADOPTION_H_
#define CHROME_APP_CREST_PROFILE_ADOPTION_H_

// Finishes the engine profile adoption that
// `crest::AdoptProductUserDataDirectory` started.
//
// That step runs in the executable's `main`, before the Chromium framework is
// loaded, so it can only move directories. Two pieces of adoption are JSON
// edits and therefore live here instead, in the browser process, at the first
// point where `base` is usable and no preference store has been read yet:
//
//   * an adopted profile directory is unregistered until its
//   `profile.info_cache`
//     entry moves with it, and
//   * an adopted profile's encrypted tracked-preference validators are bound to
//     the OSCrypt key of whichever bundle wrote them, so they must be retired
//     before a differently keyed bundle opens the profile and resets it.
//
// This is consumed by `ChromeMainDelegate::PreSandboxStartup`, immediately
// after `InitializeUserDataDir` and only in the browser process. It runs before
// `ChromeFeatureListCreator` builds the local-state `PrefService` and therefore
// long before `ProfileManager` exists.

#include <stdio.h>

#include <algorithm>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/files/important_file_writer.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/strings/string_split.h"
#include "base/values.h"
#include "chrome/app/crest_user_data_dir.h"

namespace crest {

namespace internal {

// Missing metadata needs no repair. Unreadable or corrupt existing metadata
// is a failure, never permission to replace it with an empty object.
inline std::optional<base::DictValue> ReadJsonObject(
    const base::FilePath& path) {
  if (!base::PathExists(path))
    return base::DictValue();
  std::string contents;
  if (!base::ReadFileToString(path, &contents)) {
    return std::nullopt;
  }
  return base::JSONReader::ReadDict(contents, base::JSON_PARSE_RFC);
}

inline bool WriteJsonObject(const base::FilePath& path,
                            const base::DictValue& value) {
  std::string contents;
  if (!base::JSONWriter::Write(value, &contents)) {
    return false;
  }
  return base::ImportantFileWriter::WriteFileAtomically(path, contents);
}

// Removes every encrypted tracked-preference validator from one `protection`
// subtree. Encrypted hashes are stored inside `protection.macs` under a key
// suffixed `_encrypted_hash` — atomic preferences hold a string there and split
// preferences a dictionary — and `protection.super_encrypted_hash` covers them.
//
// The legacy `protection.macs` HMACs are deliberately left in place: they are
// what keeps the profile trusted once the encrypted hashes are gone, and
// Chromium re-derives the encrypted hashes from them on the next write.
inline bool StripEncryptedHashes(base::DictValue& node) {
  std::vector<std::string> removals;
  bool changed = false;
  for (auto entry : node) {
    if (entry.first.ends_with("_encrypted_hash")) {
      removals.push_back(entry.first);
    } else if (entry.second.is_dict()) {
      changed |= StripEncryptedHashes(entry.second.GetDict());
    }
  }
  for (const std::string& key : removals) {
    node.Remove(key);
    changed = true;
  }
  return changed;
}

// Retires the encrypted validators in one preference file of an adopted
// profile. Returns success, including an absent file or one needing no edits.
inline bool RetireEncryptedValidators(const base::FilePath& path) {
  std::optional<base::DictValue> preferences = ReadJsonObject(path);
  if (!preferences) {
    return false;
  }
  base::DictValue* protection = preferences->FindDict("protection");
  if (!protection) {
    return true;
  }
  bool changed = protection->Remove("super_encrypted_hash");
  if (base::DictValue* macs = protection->FindDict("macs")) {
    changed |= StripEncryptedHashes(*macs);
  }
  if (!changed) {
    return true;
  }
  return WriteJsonObject(path, *preferences);
}

// Moves the registry entries that name `adopted` out of the previous root's
// `Local State` and into the new root's. Only the keys that name a profile
// directory are touched; everything else in either file belongs to whichever
// Chromium wrote it.
inline bool CarryProfileRegistry(const base::FilePath& previous_root,
                                 const base::FilePath& user_data_dir,
                                 const std::vector<std::string>& adopted) {
  std::optional<base::DictValue> previous =
      ReadJsonObject(previous_root.Append("Local State"));
  if (!previous)
    return false;
  if (previous->empty())
    return true;
  const base::FilePath destination = user_data_dir.Append("Local State");
  auto destination_state = ReadJsonObject(destination);
  if (!destination_state)
    return false;
  base::DictValue local_state = std::move(*destination_state);

  const base::DictValue* previous_cache =
      previous->FindDictByDottedPath("profile.info_cache");
  base::DictValue* cache =
      local_state.EnsureDict("profile")->EnsureDict("info_cache");
  std::vector<std::string> registered;
  const auto is_registered = [&registered](const std::string& name) {
    return std::find(registered.begin(), registered.end(), name) !=
           registered.end();
  };
  for (const std::string& name : adopted) {
    if (cache->contains(name)) {
      registered.push_back(name);
      continue;
    }
    const base::Value* entry =
        previous_cache ? previous_cache->Find(name) : nullptr;
    if (!entry) {
      // The previous root never registered this directory either, so there is
      // nothing to carry; Chromium registers it when the core opens it.
      continue;
    }
    cache->Set(name, entry->Clone());
    registered.push_back(name);
  }
  if (registered.empty() && cache->empty()) {
    local_state.RemoveByDottedPath("profile.info_cache");
  }

  // `profiles_order` and `last_active_profiles` are lists of directory names.
  // Adopted names keep their previous relative order and are appended after
  // whatever the new root already lists.
  for (const char* key :
       {"profile.profiles_order", "profile.last_active_profiles"}) {
    const base::ListValue* source = previous->FindListByDottedPath(key);
    if (!source) {
      continue;
    }
    base::ListValue carried;
    if (const base::ListValue* existing =
            local_state.FindListByDottedPath(key)) {
      carried = existing->Clone();
    }
    for (const base::Value& name : *source) {
      const std::string* text = name.GetIfString();
      if (!text || !is_registered(*text) ||
          std::find(carried.begin(), carried.end(), name) != carried.end()) {
        continue;
      }
      carried.Append(name.Clone());
    }
    if (!carried.empty()) {
      local_state.SetByDottedPath(key, std::move(carried));
    }
  }

  const std::string* last_used =
      previous->FindStringByDottedPath("profile.last_used");
  if (last_used && is_registered(*last_used) &&
      !local_state.FindStringByDottedPath("profile.last_used")) {
    local_state.SetByDottedPath("profile.last_used", *last_used);
  }

  if (!WriteJsonObject(destination, local_state)) {
    fprintf(stderr,
            "Crest: cannot write %s; the adopted engine profiles stay "
            "unregistered.\n",
            destination.AsUTF8Unsafe().c_str());
    return false;
  }
  for (const std::string& name : registered) {
    fprintf(stderr, "Crest: registered adopted engine profile %s.\n",
            name.c_str());
  }
  return true;
}

}  // namespace internal

// Finish only after all metadata writes succeed. A failure keeps the plan and
// stops before any profile opens. The next launch safely repeats the edits.
inline void CompleteProfileAdoption(const base::FilePath& user_data_dir) {
  const base::FilePath record = user_data_dir.Append(AdoptionRecordName());
  if (!base::PathExists(record))
    return;
  ProfileAdoptionLock lock(user_data_dir.value());
  if (!base::PathExists(record))
    return;
  std::string previous;
  std::vector<std::string> adopted;
  if (!ReadAdoptionRecord(user_data_dir.value(), previous, adopted) ||
      (!adopted.empty() &&
       !internal::CarryProfileRegistry(base::FilePath(previous), user_data_dir,
                                       adopted))) {
    StopProfileAdoption(user_data_dir.value());
  }
  for (const std::string& name : adopted) {
    const base::FilePath profile = user_data_dir.Append(name);
    if (!base::DirectoryExists(profile) ||
        !internal::RetireEncryptedValidators(
            profile.Append("Secure Preferences")) ||
        !internal::RetireEncryptedValidators(profile.Append("Preferences"))) {
      StopProfileAdoption(user_data_dir.value());
    }
  }
  if (rename(record.value().c_str(),
             user_data_dir.Append(CompletedAdoptionRecordName())
                 .value()
                 .c_str()) != 0 ||
      !SyncDirectory(user_data_dir.value())) {
    StopProfileAdoption(user_data_dir.value());
  }
}

}  // namespace crest

#endif  // CHROME_APP_CREST_PROFILE_ADOPTION_H_
