# Define a wrapper function for curl
curl() {
  # Check if the URL being called targets GitHub API
  local is_github_api=false
  for arg in "$@"; [[ "$arg" == *"api.github.com"* ]] && is_github_api=true

  # If it's a GitHub API call and GITHUB_TOKEN is available, inject headers
  if [[ "$is_github_api" = true ]] && [[ -n "$GITHUB_TOKEN" ]]; then
    command curl -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"
  else
    # Fallback to normal curl behavior
    command curl "$@"
  fi
}