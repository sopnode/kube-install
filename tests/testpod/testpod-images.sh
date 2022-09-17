# echo the image name as in the yaml

function normalize-image() {
    local name="$1"; shift
    case "$name" in
        fping)  echo localhost/fedora-with-ping ;;
        uping)  echo localhost/ubuntu-with-ping ;;
        fedora) echo fedora:latest ;;
        ubuntu) echo localhost/ubuntu:latest ;;
        kiada)  echo luksa/kiada:0.1 ;;
    esac
}