# echo the image name as in the yaml

function normalize-image() {
    local name="$1"; shift
    case "$name" in
        kiada) echo luksa/kiada:0.1 ;;
        fedora) echo fedora:latest ;;
        fping)  echo localhost/fedora-with-ping ;;
        ubuntu)  echo localhost/ubuntu:latest ;;
        uping)  echo localhost/ubuntu-with-ping ;;
    esac
}