extends RefCounted


static func run(suite: RefCounted) -> void:
	print("SeedService")
	suite.run_test("derivation is stable", func() -> void:
		var first := SeedService.derive_seed(42, &"route", "frost/0")
		var second := SeedService.derive_seed(42, &"route", "frost/0")
		suite.assert_equal(first, second)
		suite.assert_equal(first, 8516802760770355622, "Pinned derivation vector changed")
		suite.assert_equal(SeedService.signature(42, &"route", "frost/0"), "7631c2fca9c881a6")
	)
	suite.run_test("domains are isolated", func() -> void:
		suite.assert_not_equal(
			SeedService.derive_seed(42, &"route", "frost/0"),
			SeedService.derive_seed(42, &"decoration", "frost/0")
		)
	)
	suite.run_test("rng sequences reproduce", func() -> void:
		var first := SeedService.create_rng(817263, &"rewards", "branch/a")
		var second := SeedService.create_rng(817263, &"rewards", "branch/a")
		var expected := PackedInt64Array([
			231202816,
			2963517864,
			2770994871,
			33454669,
			3626191898,
			3938570752,
			3734018874,
			463279276,
		])
		for index in expected.size():
			var first_value := first.randi()
			suite.assert_equal(first_value, second.randi(), "Sequence differed at draw %d" % index)
			suite.assert_equal(first_value, expected[index], "Pinned RNG vector changed at draw %d" % index)
	)
	suite.run_test("user text seeds normalize case and whitespace", func() -> void:
		suite.assert_equal(
			SeedService.parse_user_seed("  North Wind "),
			SeedService.parse_user_seed("north wind")
		)
	)
	suite.run_test("numeric seed is preserved", func() -> void:
		suite.assert_equal(SeedService.parse_user_seed("-12345"), -12345)
	)
