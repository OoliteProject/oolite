# Define a wrapper function for curl that inject headers if a GitHub URL and GITHUB_TOKEN are available

curl() {
  # Check if the URL being called targets GitHub
  local is_github=false
  for arg in "$@"; do
    if [[ "$arg" == *"github.com"* ]]; then
      is_github=true
      break
    fi
  done

  # If it's a GitHub URL and GITHUB_TOKEN is available, inject headers
  if [[ "$is_github" = true ]] && [[ -n "$GITHUB_TOKEN" ]]; then
    command curl -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"
  else
    # Fallback to normal curl behavior
    command curl "$@"
  fi
}