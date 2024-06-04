package authz

default allow = false

allow {
    input.user == "Rig Operator"
    input.action == "approve"
    input.resource == "plan"
}

allow {
    input.user == "Remote Operator"
    input.action == "load"
    input.resource == "plan"
}
