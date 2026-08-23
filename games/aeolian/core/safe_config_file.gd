class_name SafeConfigFile
extends RefCounted

## Writes ConfigFile data via a temporary file and retains the previous valid file
## as `.bak`. Exact paths are supplied by the owning settings/profile service.


static func save(config: ConfigFile, path: String) -> Error:
	var temporary_path := path + ".tmp"
	var backup_path := path + ".bak"
	var error := config.save(temporary_path)
	if error != OK:
		return error
	var verification := ConfigFile.new()
	error = verification.load(temporary_path)
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return error

	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)

	var moved_valid_main := false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup_path):
			error = DirAccess.remove_absolute(absolute_backup)
			if error != OK:
				DirAccess.remove_absolute(absolute_temporary)
				return error
		error = DirAccess.rename_absolute(absolute_path, absolute_backup)
		if error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return error
		moved_valid_main = true

	error = DirAccess.rename_absolute(absolute_temporary, absolute_path)
	if error != OK:
		if moved_valid_main and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		DirAccess.remove_absolute(absolute_temporary)
	return error
