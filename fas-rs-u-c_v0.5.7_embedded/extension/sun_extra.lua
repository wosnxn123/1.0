API_VERSION = 4

function load_fas()
    log_info("[extra_policy] fas-rs load_fas, set extra_policy")
    set_extra_policy_rel(0, 6, -150000, -100000)
end

function unload_fas()
    log_info("[extra_policy] fas-rs unload_fas, remove extra_policy")
    remove_extra_policy(0)
end
