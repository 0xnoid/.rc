# WSL SSH autoadd keys
if ! ssh-add -l >/dev/null 2>&1; then
  eval "$(ssh-agent -s)" >/dev/null
fi

for key in ~/.ssh/*; do
  # Skip files
  [ -f "$key" ] || continue
  case "$(basename "$key")" in
    *.pub|known_hosts|known_hosts.*|config|authorized_keys|authorized_keys.*)
      continue
      ;;
  esac
  # Apply permissions and load
  chmod 600 "$key" 2>/dev/null
  ssh-add "$key" >/dev/null 2>&1
done
