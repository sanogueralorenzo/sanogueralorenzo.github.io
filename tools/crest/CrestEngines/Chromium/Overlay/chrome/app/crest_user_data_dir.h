// Copyright 2025 The Crest Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_APP_CREST_USER_DATA_DIR_H_
#define CHROME_APP_CREST_USER_DATA_DIR_H_

// Runs before the Chromium framework is loaded. Keep profile adoption in libc
// and libc++ until the browser process can finish its JSON metadata edits.
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/errno.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <string>
#include <vector>

namespace crest {

inline bool IsDirectory(const std::string& path) {
  struct stat info;
  return stat(path.c_str(), &info) == 0 && S_ISDIR(info.st_mode);
}

inline bool PathExists(const std::string& path) {
  struct stat info;
  return lstat(path.c_str(), &info) == 0 || errno != ENOENT;
}

inline bool SyncDirectory(const std::string& path) {
  const int file = open(path.c_str(), O_RDONLY | O_DIRECTORY);
  if (file < 0) {
    return false;
  }
  const bool synced = fsync(file) == 0;
  close(file);
  return synced;
}

inline bool MakeDirectoryTree(const std::string& path) {
  if (IsDirectory(path)) {
    return true;
  }
  const auto separator = path.find_last_of('/');
  const std::string parent = path.substr(0, separator);
  if (separator != std::string::npos && separator > 0 &&
      !MakeDirectoryTree(parent)) {
    return false;
  }
  if (mkdir(path.c_str(), 0700) != 0 && !IsDirectory(path)) {
    return false;
  }
  return separator == std::string::npos || separator == 0 ||
         SyncDirectory(parent);
}

// A record never admits paths, only immediate profile directory names.
inline bool IsCrestProfileName(const std::string& name) {
  return name.starts_with("Crest-") && name.size() > 6 &&
         name.find_first_of("/\r\n") == std::string::npos;
}

// A failed migration must not open one half of a split profile set. Retaining
// the record lets the next launch retry after the filesystem problem is fixed.
[[noreturn]] inline void StopProfileAdoption(const std::string& directory) {
  fprintf(stderr,
          "Crest: cannot finish profile adoption in %s. Existing profiles "
          "were preserved. Resolve the filesystem error and reopen Crest.\n",
          directory.c_str());
  exit(EXIT_FAILURE);
}

inline std::vector<std::string> CrestProfileDirectories(
    const std::string& directory) {
  std::vector<std::string> names;
  DIR* handle = opendir(directory.c_str());
  if (!handle) {
    if (errno != ENOENT)
      StopProfileAdoption(directory);
    return names;
  }
  while (struct dirent* entry = readdir(handle)) {
    const std::string name(entry->d_name);
    if (IsCrestProfileName(name) && IsDirectory(directory + "/" + name)) {
      names.push_back(name);
    }
  }
  closedir(handle);
  std::sort(names.begin(), names.end());
  return names;
}

inline const char* AdoptionRecordName() {
  return "Crest Adoption";
}

inline const char* CompletedAdoptionRecordName() {
  return "Crest Adoption Complete";
}

// Serialize both stages across simultaneous launches. Each stage releases its
// lock before the browser proceeds; normal single-instance routing stays
// intact.
class ProfileAdoptionLock {
 public:
  explicit ProfileAdoptionLock(const std::string& directory)
      : file_(open((directory + "/Crest Adoption Lock").c_str(),
                   O_CREAT | O_RDWR,
                   0600)) {
    if (file_ < 0 || flock(file_, LOCK_EX) != 0) {
      StopProfileAdoption(directory);
    }
  }
  ~ProfileAdoptionLock() { close(file_); }
  ProfileAdoptionLock(const ProfileAdoptionLock&) = delete;
  ProfileAdoptionLock& operator=(const ProfileAdoptionLock&) = delete;

 private:
  int file_;
};

// Commit the complete plan before the first rename. The legacy record format
// stays readable: its first line is the source root, followed by profile names.
inline bool WriteAdoptionRecord(const std::string& preferred,
                                const std::string& previous,
                                const std::vector<std::string>& adopted) {
  if (previous.find_first_of("\r\n") != std::string::npos) {
    return false;
  }
  const std::string path = preferred + "/" + AdoptionRecordName();
  std::string temporary = path + ".XXXXXX";
  const int descriptor = mkstemp(temporary.data());
  if (descriptor < 0) {
    return false;
  }
  FILE* file = fdopen(descriptor, "w");
  if (!file) {
    close(descriptor);
    unlink(temporary.c_str());
    return false;
  }
  bool written = fprintf(file, "%s\n", previous.c_str()) >= 0;
  for (const std::string& name : adopted) {
    written = IsCrestProfileName(name) &&
              fprintf(file, "%s\n", name.c_str()) >= 0 && written;
  }
  written = fflush(file) == 0 && written;
  written = fsync(descriptor) == 0 && written;
  written = fclose(file) == 0 && written;
  if (!written || rename(temporary.c_str(), path.c_str()) != 0) {
    unlink(temporary.c_str());
    return false;
  }
  return SyncDirectory(preferred);
}

inline bool ReadAdoptionRecord(const std::string& preferred,
                               std::string& previous,
                               std::vector<std::string>& adopted) {
  FILE* file = fopen((preferred + "/" + AdoptionRecordName()).c_str(), "r");
  if (!file) {
    return false;
  }
  char* line = nullptr;
  size_t capacity = 0;
  bool valid = true;
  bool first = true;
  while (getline(&line, &capacity, file) >= 0) {
    std::string value(line);
    if (value.empty() || value.back() != '\n') {
      valid = false;
      break;
    }
    value.pop_back();
    if (first) {
      previous = value;
      valid = !value.empty() && value.front() == '/' &&
              value.find('\r') == std::string::npos;
      first = false;
    } else {
      valid = IsCrestProfileName(value) &&
              std::find(adopted.begin(), adopted.end(), value) == adopted.end();
      if (valid)
        adopted.push_back(value);
    }
    if (!valid)
      break;
  }
  valid = valid && !first && !ferror(file);
  free(line);
  fclose(file);
  return valid;
}

inline std::string AdoptProductUserDataDirectory(const std::string& home) {
  const std::string support = home + "/Library/Application Support";
  const std::string preferred = support + "/Crest/Chromium";
  const std::string previous = support + "/Chromium";
  if (!MakeDirectoryTree(preferred)) {
    StopProfileAdoption(preferred);
  }
  ProfileAdoptionLock lock(preferred);
  if (PathExists(preferred + "/" + CompletedAdoptionRecordName())) {
    return preferred;
  }
  std::vector<std::string> names;
  if (PathExists(preferred + "/" + AdoptionRecordName())) {
    std::string recorded_previous;
    if (!ReadAdoptionRecord(preferred, recorded_previous, names) ||
        recorded_previous != previous) {
      StopProfileAdoption(preferred);
    }
  } else {
    names = CrestProfileDirectories(previous);
    // An older build may have stopped before writing its record. Include
    // already moved directories so their metadata is repaired as well.
    for (const std::string& name : CrestProfileDirectories(preferred)) {
      if (std::find(names.begin(), names.end(), name) == names.end())
        names.push_back(name);
    }
    if (!WriteAdoptionRecord(preferred, previous, names)) {
      StopProfileAdoption(preferred);
    }
  }
  for (const std::string& name : names) {
    const std::string source = previous + "/" + name;
    const std::string destination = preferred + "/" + name;
    if (PathExists(destination)) {
      if (PathExists(source) || !IsDirectory(destination))
        StopProfileAdoption(preferred);
      continue;
    }
    if (!IsDirectory(source) ||
        rename(source.c_str(), destination.c_str()) != 0 ||
        !SyncDirectory(previous) || !SyncDirectory(preferred)) {
      StopProfileAdoption(preferred);
    }
    fprintf(stderr, "Crest: adopted engine profile %s into %s.\n", name.c_str(),
            preferred.c_str());
  }
  return preferred;
}

}  // namespace crest

#endif  // CHROME_APP_CREST_USER_DATA_DIR_H_
