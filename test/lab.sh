#!/usr/bin/env bash
# What the README promises, checked from inside the lab's own network and through docker exec,
# which is how the platform's terminal reaches the lab's Python: run by check.sh.
set -euo pipefail
: "${NET:?run through test/check.sh}"
: "${CID:?run through test/check.sh}"
probe() { docker run --rm --network "$NET" lab-check-probe bash -c "$1"; }
run() { docker exec "$CID" "$@"; }
has() { grep -Fxq -- "$1" <<<"$out" || { echo "no line '$1' in: $out" >&2; exit 1; }; }

echo "- JupyterLab answers with no token to type"
probe '
set -eu
code=$(curl -s -o /dev/null -w "%{http_code}" http://jupyter:8888/lab)
[ "$code" = 200 ] || { echo "JupyterLab answered $code" >&2; exit 1; }
curl -fs http://jupyter:8888/api/contents | grep -q "start.ipynb" || { echo "no start.ipynb" >&2; exit 1; }
curl -fs http://jupyter:8888/api/contents | grep -q "\"site\"" || { echo "no site folder" >&2; exit 1; }
curl -fs -H "Host: someone-8888.example.com" -H "Origin: https://someone-8888.example.com" \
  http://jupyter:8888/api/kernelspecs | grep -q python3 || { echo "a proxied host is refused" >&2; exit 1; }
echo "- the Preview page on 8000 serves the three files"
curl -fs http://jupyter:8000/ | grep -q "<title>Lunch menu</title>" || { echo "preview is not the page" >&2; exit 1; }
curl -fs http://jupyter:8000/style.css | grep -q -- "--accent" || { echo "no style.css" >&2; exit 1; }
curl -fs http://jupyter:8000/app.js | grep -q "filterDishes" || { echo "no app.js" >&2; exit 1; }
echo "- no way out to the internet"
if curl -s -m 4 -o /dev/null https://example.com; then echo "the lab reached the internet" >&2; exit 1; fi
'

echo "- the work folder holds the page, the notebook and the step scripts"
run ls site/index.html site/style.css site/app.js start.ipynb \
  steps/tags.py steps/outline.py steps/links.py steps/css.py steps/js.py steps/sizes.py steps/serve.py >/dev/null

echo "- a page edited in site/ is what the Preview serves"
run sh -c 'echo "/* edited */" >> site/style.css'
probe 'curl -fs http://jupyter:8000/style.css | grep -q "edited"' || { echo "an edit is not served" >&2; exit 1; }
run sh -c 'sed -i "\$d" site/style.css'

echo "- tags.py: 36 tags in all, 5 li, 3 section, 3 h2, 2 button"
out=$(run python3 steps/tags.py)
for want in "li 5" "section 3" "h2 3" "button 2" "tags in all: 36"; do has "$want"; done

echo "- outline.py: one h1 and three h2"
out=$(run python3 steps/outline.py)
for want in "h1 Lunch menu" "  h2 Today's dishes" "  h2 Find a dish" "  h2 Theme"; do has "$want"; done

echo "- links.py: three anchors that are found, a file here, another site"
out=$(run python3 steps/links.py)
for want in "Dishes -> #dishes (on this page, found)" "Find a dish -> #find (on this page, found)" \
  "Theme -> #theme (on this page, found)" "The script that runs this page -> app.js (a file here)" \
  "Menu notes -> https://example.org/notes (another site)"; do has "$want"; done

echo "- css.py: 17 rules, 39 declarations, padding used most"
out=$(run python3 steps/css.py)
for want in "rules: 17" "declarations: 39" "most used: padding x6, color x5, margin x3"; do has "$want"; done

echo "- js.py: two functions, three listeners, four ids"
out=$(run python3 steps/js.py)
for want in "function filterDishes" "function toggleTheme" "listens for submit" "listens for input" \
  "listens for click" "looks up id count" "looks up id find-form" "looks up id word" "looks up id theme-button"; do has "$want"; done

echo "- sizes.py: 1373, 1125 and 1093 bytes, 3591 in all"
out=$(run python3 steps/sizes.py)
for want in "index.html 1373 bytes" "style.css 1125 bytes" "app.js 1093 bytes" "total 3591 bytes"; do has "$want"; done

echo "- serve.py: the Preview answers 200 and names the page"
out=$(run python3 steps/serve.py)
for want in "status 200" "title Lunch menu" "style.css 200 text/css"; do has "$want"; done

echo "- the starter notebook runs from top to bottom inside the memory limit"
run jupyter nbconvert --to notebook --execute start.ipynb --output /tmp/ran.ipynb >/dev/null 2>&1 \
  || { echo "start.ipynb does not run" >&2; exit 1; }
echo "  ok"
