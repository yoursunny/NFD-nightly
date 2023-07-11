const BASE = "https://nfd-nightly-apt.ndn.today";

for (const $form of document.querySelectorAll("form")) {
  $form.addEventListener("submit", (evt) => evt.preventDefault());
}

const $setup = document.querySelector("#p_setup");
const $error = document.querySelector("#p_error");
const $list = document.querySelector("#p_list");
/** @type {AbortController|undefined} */
let abort;

async function update() {
  const $input = document.querySelector("input[name=os]:checked");
  if (!$input) {
    return;
  }
  const { repo, distro, arch } = $input.parentElement.dataset;
  const source = `deb [arch=${arch} trusted=yes] ${BASE}/${repo} ${distro} main`;
  $setup.textContent = `echo "${source}" \\\n  | sudo tee /etc/apt/sources.list.d/nfd-nightly.list`;

  const list = `${BASE}/${repo}/dists/${distro}/main/binary-${arch}/Packages`;
  $error.classList.add("hidden");
  $list.classList.add("hidden");
  abort?.abort();
  abort = new AbortController();
  const { signal } = abort;
  let packages = "";
  try {
    packages = await (await fetch(list, { signal })).text();
  } catch (err) {
    if (!signal.aborted) {
      $error.textContent = err.toString();
      $error.classList.remove("hidden");
    }
    return;
  }

  $list.querySelector("tbody")?.remove();
  const $tbody = document.createElement("tbody");
  for (const lines of packages.split("\n\n")) {
    /** @type {Record<string, string>} */
    const kv = {};
    for (const line of lines.split("\n")) {
      const [k, v] = line.split(":");
      kv[k.toLowerCase()] = (v ?? "").trim();
    }
    const { package: pkg, description, source, version = "?", "installed-size": installed = "?", depends = "" } = kv;
    if (!pkg || !description) {
      continue;
    }

    const $tr = document.createElement("tr");
    for (const v of [pkg, description]) {
      const $td = document.createElement("td");
      $td.textContent = v;
      $tr.append($td);
    }
    $tr.title = `Source: ${source ?? pkg}\nVersion: ${version}\nInstalled-Size: ${installed}K\n` +
                `Depends: ${depends.replace(/ \([^)]+\)/g, "")}`;
    $tbody.append($tr);
  }
  $list.append($tbody);
  $list.classList.remove("hidden");
}

for (const $input of document.querySelectorAll("input[name=os]")) {
  $input.addEventListener("change", update);
}
await update();
