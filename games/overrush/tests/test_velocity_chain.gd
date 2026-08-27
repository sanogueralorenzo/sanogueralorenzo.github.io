extends SceneTree

const VelocityChainModel = preload("res://scripts/velocity_chain.gd")

var _failures: Array[String] = []


func _init() -> void:
	var chain = VelocityChainModel.new()
	_expect(not chain.record_defeat(VelocityChainModel.QUALIFYING_SPEED - 0.1) and chain.current_count == 0, "Slow defeats should never start the movement-skill chain.")
	_expect(not chain.record_defeat(58.0) and chain.current_count == 1 and chain.get_tier_name() == "BUILDING", "A rewarding cruise-speed defeat should start a clearly named chain.")
	chain.update(2.0, 58.0)
	var timer_before_dash: float = chain.timer
	chain.record_dash()
	_expect(chain.timer > timer_before_dash and chain.timer <= VelocityChainModel.MAX_TIMER, "Dashing should grant bounded grace without increasing the chain for free.")
	_expect(not chain.record_defeat(58.0) and chain.current_count == 2, "Closely spaced high-speed defeats should extend the same chain.")
	_expect(chain.record_defeat(58.0, true) and chain.current_count == 5 and chain.get_tier_name() == "LOCKED", "An elite should carry triple chain weight and announce only a newly reached tier.")
	_expect(chain.update(1.5, 20.0) and chain.current_count == 0, "Braking below the break speed should drain the window rapidly and end the chain.")
	_expect(chain.best_count == 5 and chain.total_qualifying_defeats == 3, "A broken chain should retain honest best-chain and qualifying-defeat evidence.")

	chain.reset()
	for _index in range(30):
		chain.record_defeat(72.0)
	_expect(chain.current_count == 30 and chain.get_tier_name() == "UNBROKEN", "Sustained high-speed clears should reach the final readable tier.")
	_expect(chain.get_momentum_bonus() == 14, "A 30-chain should earn a modest deterministic non-power reward.")
	_expect(VelocityChainModel.get_momentum_bonus_for(999) == VelocityChainModel.MAX_MOMENTUM_BONUS, "Flow rewards should remain capped even for extreme late-run packs.")
	chain.reset()
	_expect(chain.current_count == 0 and chain.best_count == 0 and is_zero_approx(chain.timer), "Starting a run should clear all prior chain state.")

	if _failures.is_empty():
		print("Velocity chain validation passed — speed gates, dash grace, elite weight, tiers, break pressure, and bounded rewards agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
