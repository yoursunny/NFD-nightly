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
  const $label = $input.parentElement;
  const repo = $label.getAttribute("data-repo");
  const distro = $label.getAttribute("data-distro");
  const arch = $label.getAttribute("data-arch");
  const source = `deb [arch=${arch} trusted=yes] https://nfd-nightly-apt.ndn.today/${repo} ${distro} main`;
  $setup.textContent = `echo "${source}" \\\n  | sudo tee /etc/apt/sources.list.d/nfd-nightly.list`;

  const list = `https://nfd-nightly-apt.ndn.today/${repo}/dists/${distro}/main/binary-${arch}/Packages`;
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
    const kv = {};
    for (const line of lines.split("\n")) {
      const [k, v] = line.split(":");
      kv[k.toLowerCase()] = (v ?? "").trim();
    }

    const $tr = document.createElement("tr");
    let missing = false;
    for (const k of ["package", "description"]) {
      const v = kv[k];
      if (!v) {
        missing = true;
        break;
      }
      const $td = document.createElement("td");
      $td.textContent = v;
      $tr.append($td);
    }
    if (missing) {
      continue;
    }
    $tbody.append($tr);
  }
  $list.append($tbody);
  $list.classList.remove("hidden");
}

for (const $input of document.querySelectorAll("input[name=os]")) {
  $input.addEventListener("change", update);
}
update();
