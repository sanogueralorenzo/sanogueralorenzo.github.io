extends RefCounted


static func run(suite: RefCounted) -> void:
	print("SafeConfigFile")
	suite.run_test("save round trip and backup", func() -> void:
		var unique := "user://aeolian-tests-%d.cfg" % Time.get_ticks_usec()
		var first := ConfigFile.new()
		first.set_value("test", "value", 11)
		suite.assert_equal(SafeConfigFile.save(first, unique), OK)
		var loaded := ConfigFile.new()
		suite.assert_equal(loaded.load(unique), OK)
		suite.assert_equal(loaded.get_value("test", "value"), 11)

		var second := ConfigFile.new()
		second.set_value("test", "value", 22)
		suite.assert_equal(SafeConfigFile.save(second, unique), OK)
		var backup := ConfigFile.new()
		suite.assert_equal(backup.load(unique + ".bak"), OK)
		suite.assert_equal(backup.get_value("test", "value"), 11)
		_remove(unique)
		_remove(unique + ".bak")
		_remove(unique + ".tmp")
	)
	suite.run_test("corrupt main never replaces valid backup", func() -> void:
		var unique := "user://aeolian-tests-recovery-%d.cfg" % Time.get_ticks_usec()
		var first := ConfigFile.new()
		first.set_value("test", "value", 11)
		suite.assert_equal(SafeConfigFile.save(first, unique), OK)
		var second := ConfigFile.new()
		second.set_value("test", "value", 22)
		suite.assert_equal(SafeConfigFile.save(second, unique), OK)
		_write_corrupt(unique)
		var quarantine := unique + ".known-corrupt"
		suite.assert_equal(DirAccess.rename_absolute(
			ProjectSettings.globalize_path(unique),
			ProjectSettings.globalize_path(quarantine)
		), OK)

		var third := ConfigFile.new()
		third.set_value("test", "value", 33)
		suite.assert_equal(SafeConfigFile.save(third, unique), OK)
		var backup := ConfigFile.new()
		suite.assert_equal(backup.load(unique + ".bak"), OK)
		suite.assert_equal(backup.get_value("test", "value"), 11)

		_write_corrupt(unique)
		var recovered := ConfigFile.new()
		suite.assert_equal(recovered.load(unique + ".bak"), OK)
		suite.assert_equal(recovered.get_value("test", "value"), 11)
		_remove(unique)
		_remove(unique + ".bak")
		_remove(unique + ".tmp")
		_remove(quarantine)
	)


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _write_corrupt(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("[not valid config")
		file.close()
