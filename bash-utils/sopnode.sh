## kubectl set of aliases
# not super useful though...
alias kdp='kubectl describe pod'
# kubectl apply
alias kap='kubectl apply'
# kubectl delete
alias krm='kubectl delete'
alias krmf='kubectl delete -f'
# kubectl services
alias kgsvc='kubectl get service'
# kubectl deployments
alias kgdep='kubectl get deployments'
# kubectl misc
alias kl='kubectl logs'
alias kei='kubectl exec -it'
alias kns='kubectl config set-context --current --namespace '


function -fit-nodes() {
    k-nodes | grep '^fit'
}

function fit-nodes() {
    export FIT_NODES=$(-fit-nodes)
    echo FIT_NODES=\"$(echo $FIT_NODES)\"
}

function -fit-alives() {
    k-alives | grep '^fit'
}

function fit-alives() {
    export FIT_ALIVES=$(-fit-alives)
    echo FIT_ALIVES=\"$(echo $FIT_ALIVES)\"
}

function -fit-deads() {
    k-deads | grep '^fit'
}

function fit-deads() {
    export FIT_DEADS=$(-fit-deads)
    echo FIT_DEADS=\"$(echo $FIT_DEADS)\"
}

function fit-label-nodes() {
    local nodes=$(-fit-nodes)
    [ -z "$nodes" ] && { echo "no fit node currently in the cluster"; return 1; }
    kubectl label nodes $nodes r2lab/node=true
}

###
function fit-drain-nodes() {
    local nodes="$@"
    local node
    [ -z "$nodes" ] && nodes=$(-fit-nodes)
    for node in $nodes; do
        local command="kubectl drain --force --ignore-daemonsets $node"
        echo "draining $node: $command"
        $command
    done
}

function fit-delete-nodes() {
    local nodes="$@"
    local node
    [ -z "$nodes" ] && nodes=$(-fit-nodes)
    for node in $nodes; do
        local command="kubectl delete node $node"
        echo "deleting $node: $command"
        $command
    done
}

alias ki=kube-install.sh

function cdki() {
    local cd
    cd=$(ki pwd) && cd $cd
}
