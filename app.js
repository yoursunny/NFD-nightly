import { el, mount } from "https://cdn.jsdelivr.net/npm/redom@3.27.1/dist/redom.es.min.js";

const PROJ = [
  { id: "ndn-cxx" },
  { id: "nfd", title: "NFD" },
  { id: "ndn-tools" },
  { id: "libpsync", title: "PSync" },
  { id: "name-based-access-control", title: "NAC" },
];

/** @type {HTMLParagraphElement} */
const $msg = document.querySelector("#msg");

/** @type {HTMLTableSectionElement} */
const $tbody = el("tbody");

function renderArtifacts(run, artifacts) {
  const suite = run.check_suite_url.split("/").pop();
  const platforms = artifacts.filter((a) => a.name.startsWith("ndn-cxx ")).map((a) => a.name.slice(8));
  if (platforms.length === 0) {
    return;
  }

  const rows = [];
  for (const platform of platforms) {
    const $tr = el("tr",
      el("td", platform),
    );
    for (const { id } of PROJ) {
      const artifact = artifacts.find((a) => a.name === `${id} ${platform}`);
      if (artifact) {
        const href = `https://github.com/yoursunny/NFD-nightly/suites/${suite}/artifacts/${artifact.id}`;
        mount($tr,
          el("td",
            el("a", { href, target: "_blank", rel: "noopener" }, "download"),
          ),
        );
      } else {
        mount($tr,
          el("td", "-"),
        );
      }
    }
    rows.push($tr);
  }

  mount(rows[0],
    el("td",
      { rowSpan: platforms.length },
      `${run.id}`,
      el("br"),
      el("small", run.updated_at),
    ),
    rows[0].firstChild,
  );

  rows.forEach(($tr) => mount($tbody, $tr));
}

(async () => {
  $msg.textContent = "loading";
  const since = Date.now() - 30 * 86400000;

  const { workflow_runs: runs } = await (await fetch("https://api.github.com/repos/yoursunny/NFD-nightly/actions/runs")).json();
  for (const run of runs) {
    if (run.conclusion !== "success" ||
        run.head_branch !== "main" ||
        Date.parse(run.updated_at) < since) {
      continue;
    }

    try {
      const { artifacts } = await (await fetch(run.artifacts_url, { cache: "force-cache" })).json();
      renderArtifacts(run, artifacts);
    } catch (err) {
      console.error(err);
    }
  }
})().then(() => {
  const $table = el("table.pure-table.pure-table-horizontal",
    el("thead",
      el("tr",
        el("th", "build"),
        el("th", "platform"),
        ...PROJ.map(({ id, title }) => el("th", title ?? id)),
      ),
    ),
    $tbody,
  );
  mount(document.querySelector("#table"), $table);
  $msg.remove();
}, (err) => {
  console.error(err);
  $msg.textContent = err;
});
