-- Bridge so `:checkhealth doctor` reports the same dependency probes the
-- palette's Doctor category and :Doctor use (util/doctor).
return {
    check = function()
        require("util.doctor").health()
    end,
}
