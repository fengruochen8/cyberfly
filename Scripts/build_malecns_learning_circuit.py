#!/usr/bin/env python3
"""Build the auditable MaleCNS olfactory learning subgraph used by CyberFly V2."""

from __future__ import annotations

import hashlib
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.feather as feather
import pyarrow.ipc as ipc


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = PROJECT_ROOT / "Data" / "raw"
GENERATED_DIR = PROJECT_ROOT / "Data" / "generated"
SWIFT_OUTPUT = (
    PROJECT_ROOT
    / "Sources"
    / "CyberFlySimulation"
    / "Generated"
    / "MaleCNSLearningCircuitData.swift"
)
JSON_OUTPUT = GENERATED_DIR / "male-cns-olfactory-learning-v1.json"

ANNOTATIONS = RAW_DIR / "body-annotations-male-cns-v1.0-minconf-0.5.feather"
NEUROTRANSMITTERS = RAW_DIR / "body-neurotransmitters-male-cns-v1.0.feather"
WEIGHTS = RAW_DIR / "connectome-weights-male-cns-v1.0-minconf-0.5.feather"

DATASET_ID = "male-cns:v1.0"
CIRCUIT_ID = "DM1/DM2→KC→MBON01/11↔PAM01/PPL101"
ODOR_TYPES = {"ORN_DM1", "ORN_DM2"}
PN_TYPES = {"DM1_lPN", "DM2_lPN"}
MBON_TYPES = {"MBON01", "MBON11"}
DAN_TYPES = {"PAM01", "PPL101"}
APL_TYPES = {"APL"}
EXPECTED_KENYON_COUNT = 1240
EXPECTED_NEURON_COUNT = 1426
SOURCE_URL_PREFIX = (
    "https://storage.googleapis.com/flyem-male-cns/v1.0/"
    "connectome-data/flat-connectome/"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def side_for(row: dict) -> str:
    side = row.get("somaSide")
    if side in {"L", "R"}:
        return side
    instance = row.get("instance") or ""
    if instance.endswith("_L"):
        return "L"
    if instance.endswith("_R"):
        return "R"
    return "U"


def filter_rows(batch: pa.RecordBatch, pre_ids: set[int], post_ids: set[int]) -> list[dict]:
    if not pre_ids or not post_ids:
        return []
    mask = pc.and_(
        pc.is_in(batch.column("body_pre"), value_set=pa.array(sorted(pre_ids), type=pa.int64())),
        pc.is_in(batch.column("body_post"), value_set=pa.array(sorted(post_ids), type=pa.int64())),
    )
    filtered = batch.filter(mask)
    return [
        {"bodyPre": pre, "bodyPost": post, "observedSynapseCount": weight}
        for pre, post, weight in zip(
            filtered.column("body_pre").to_pylist(),
            filtered.column("body_post").to_pylist(),
            filtered.column("weight").to_pylist(),
            strict=True,
        )
    ]


def first_pass(
    path: Path,
    projection_ids: set[int],
    kenyon_ids: set[int],
    mbon_ids: set[int],
) -> tuple[list[dict], list[dict]]:
    pn_to_kc: list[dict] = []
    kc_to_mbon: list[dict] = []
    with pa.memory_map(str(path), "r") as source:
        reader = ipc.open_file(source)
        for index in range(reader.num_record_batches):
            batch = reader.get_batch(index)
            pn_to_kc.extend(filter_rows(batch, projection_ids, kenyon_ids))
            kc_to_mbon.extend(filter_rows(batch, kenyon_ids, mbon_ids))
    return pn_to_kc, kc_to_mbon


def selected_edges(
    path: Path,
    odor_ids: set[int],
    projection_ids: set[int],
    kenyon_ids: set[int],
    mbon_ids: set[int],
    dan_ids: set[int],
    apl_ids: set[int],
) -> list[dict]:
    pathways = (
        ("ORN_TO_PN", odor_ids, projection_ids),
        ("PN_TO_KC", projection_ids, kenyon_ids),
        ("KC_TO_MBON", kenyon_ids, mbon_ids),
        ("DAN_TO_TARGET", dan_ids, kenyon_ids | mbon_ids),
        ("TARGET_TO_DAN", kenyon_ids | mbon_ids, dan_ids),
        ("KC_TO_APL", kenyon_ids, apl_ids),
        ("APL_TO_KC", apl_ids, kenyon_ids),
    )
    edges: list[dict] = []
    with pa.memory_map(str(path), "r") as source:
        reader = ipc.open_file(source)
        for index in range(reader.num_record_batches):
            batch = reader.get_batch(index)
            for pathway, pre_ids, post_ids in pathways:
                for edge in filter_rows(batch, pre_ids, post_ids):
                    edge["pathway"] = pathway
                    edge["provenance"] = "observed"
                    edges.append(edge)
    return sorted(edges, key=lambda edge: (edge["pathway"], edge["bodyPre"], edge["bodyPost"]))


def swift_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def build_swift(
    kenyon_rows: list[dict],
    pn_to_kc: list[dict],
    kc_to_mbon: list[dict],
    type_by_body: dict[int, str],
    source_hashes: dict[str, str],
    population_counts: dict[str, int],
    pathway_synapses: dict[str, int],
) -> str:
    pn_inputs: dict[int, Counter[str]] = defaultdict(Counter)
    for edge in pn_to_kc:
        pn_inputs[edge["bodyPost"]][type_by_body[edge["bodyPre"]]] += edge[
            "observedSynapseCount"
        ]

    mbon_outputs: dict[int, Counter[str]] = defaultdict(Counter)
    for edge in kc_to_mbon:
        mbon_outputs[edge["bodyPre"]][type_by_body[edge["bodyPost"]]] += edge[
            "observedSynapseCount"
        ]

    lines = [
        "// Generated by Scripts/build_malecns_learning_circuit.py. Do not hand-edit.",
        "import Foundation",
        "",
        "enum GeneratedMaleCNSLearningCircuitData {",
        f"    static let datasetID = {swift_string(DATASET_ID)}",
        f"    static let circuitID = {swift_string(CIRCUIT_ID)}",
        f"    static let realNeuronCount = {sum(population_counts.values())}",
        "    static let sourceSHA256: [String: String] = [",
    ]
    for name, digest in sorted(source_hashes.items()):
        lines.append(f"        {swift_string(name)}: {swift_string(digest)},")
    lines.extend(["    ]", "", "    static let populationCounts: [String: Int] = ["])
    for name, count in sorted(population_counts.items()):
        lines.append(f"        {swift_string(name)}: {count},")
    lines.extend(["    ]", "", "    static let pathwaySynapseCounts: [String: Int] = ["])
    for name, count in sorted(pathway_synapses.items()):
        lines.append(f"        {swift_string(name)}: {count},")
    lines.extend(["    ]", "", "    static let kenyonCells: [MaleCNSLearningKenyonDefinition] = ["])
    for row in sorted(kenyon_rows, key=lambda item: item["bodyId"]):
        body_id = row["bodyId"]
        side = {"L": "left", "R": "right", "U": "unknown"}[side_for(row)]
        inputs = pn_inputs[body_id]
        outputs = mbon_outputs[body_id]
        lines.append(
            "        .init("
            f"bodyID: {body_id}, "
            f"cellType: {swift_string(row['type'])}, "
            f"side: .{side}, "
            f"dm1InputSynapses: {inputs['DM1_lPN']}, "
            f"dm2InputSynapses: {inputs['DM2_lPN']}, "
            f"avoidanceOutputSynapses: {outputs['MBON01']}, "
            f"approachOutputSynapses: {outputs['MBON11']}),"
        )
    lines.extend(["    ]", "}", ""])
    return "\n".join(lines)


def main() -> None:
    paths = (ANNOTATIONS, NEUROTRANSMITTERS, WEIGHTS)
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise SystemExit("Missing official input files: " + ", ".join(missing))

    annotations = feather.read_table(ANNOTATIONS, memory_map=True).to_pylist()
    by_body = {row["bodyId"]: row for row in annotations}
    type_by_body = {body_id: row["type"] for body_id, row in by_body.items()}

    def ids_for_types(types: set[str]) -> set[int]:
        return {row["bodyId"] for row in annotations if row["type"] in types}

    odor_ids = ids_for_types(ODOR_TYPES)
    projection_ids = ids_for_types(PN_TYPES)
    all_kenyon_ids = {
        row["bodyId"] for row in annotations if row["class"] == "Kenyon_Cell"
    }
    mbon_ids = ids_for_types(MBON_TYPES)
    dan_ids = ids_for_types(DAN_TYPES)
    apl_ids = ids_for_types(APL_TYPES)

    all_pn_to_kc, all_kc_to_mbon = first_pass(
        WEIGHTS, projection_ids, all_kenyon_ids, mbon_ids
    )
    pn_connected = {edge["bodyPost"] for edge in all_pn_to_kc}
    mbon_connected = {edge["bodyPre"] for edge in all_kc_to_mbon}
    kenyon_ids = pn_connected & mbon_connected
    if len(kenyon_ids) != EXPECTED_KENYON_COUNT:
        raise SystemExit(
            f"Unexpected selected KC count {len(kenyon_ids)} != {EXPECTED_KENYON_COUNT}"
        )

    edges = selected_edges(
        WEIGHTS,
        odor_ids,
        projection_ids,
        kenyon_ids,
        mbon_ids,
        dan_ids,
        apl_ids,
    )
    selected_ids = odor_ids | projection_ids | kenyon_ids | mbon_ids | dan_ids | apl_ids
    if len(selected_ids) != EXPECTED_NEURON_COUNT:
        raise SystemExit(
            f"Unexpected selected neuron count {len(selected_ids)} != {EXPECTED_NEURON_COUNT}"
        )

    neurotransmitters = feather.read_table(NEUROTRANSMITTERS, memory_map=True)
    selected_array = pa.array(sorted(selected_ids), type=pa.int64())
    nt_rows = neurotransmitters.filter(
        pc.is_in(neurotransmitters["body"], value_set=selected_array)
    ).to_pylist()
    nt_by_body = {row["body"]: row for row in nt_rows}

    nodes = []
    for body_id in sorted(selected_ids):
        row = by_body[body_id]
        nt = nt_by_body.get(body_id)
        nodes.append(
            {
                "bodyId": body_id,
                "type": row["type"],
                "instance": row["instance"],
                "side": side_for(row),
                "neurotransmitter": nt["consensus_nt"] if nt else None,
                "neurotransmitterConfidence": nt["predicted_nt_confidence"] if nt else None,
                "identityProvenance": "observed",
                "neurotransmitterProvenance": "predicted" if nt else "unavailable",
            }
        )

    population_counts = Counter(node["type"] for node in nodes)
    pathway_edge_counts = Counter(edge["pathway"] for edge in edges)
    pathway_synapses = Counter()
    for edge in edges:
        pathway_synapses[edge["pathway"]] += edge["observedSynapseCount"]

    forward_pn_to_kc = [edge for edge in edges if edge["pathway"] == "PN_TO_KC"]
    forward_kc_to_mbon = [edge for edge in edges if edge["pathway"] == "KC_TO_MBON"]
    for required in ("ORN_TO_PN", "PN_TO_KC", "KC_TO_MBON", "DAN_TO_TARGET"):
        if pathway_synapses[required] <= 0:
            raise SystemExit(f"Required observed pathway is absent: {required}")

    source_hashes = {path.name: sha256(path) for path in paths}
    payload = {
        "schemaVersion": 1,
        "dataset": DATASET_ID,
        "circuit": CIRCUIT_ID,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "sourceFiles": [
            {
                "name": path.name,
                "url": SOURCE_URL_PREFIX + path.name,
                "bytes": path.stat().st_size,
                "sha256": source_hashes[path.name],
            }
            for path in paths
        ],
        "provenance": {
            "neuronIdentity": "observed",
            "synapseCount": "observed",
            "neurotransmitter": "predicted",
            "odorEncoding": "fitted-and-assumed",
            "membraneDynamics": "fitted-and-assumed",
            "dopaminePlasticity": "literature-and-fitted",
        },
        "selection": {
            "odorReceptors": sorted(ODOR_TYPES),
            "projectionNeurons": sorted(PN_TYPES),
            "outputNeurons": sorted(MBON_TYPES),
            "dopamineNeurons": sorted(DAN_TYPES),
            "feedbackNeuron": sorted(APL_TYPES),
            "kenyonRule": "postsynaptic to selected PNs and presynaptic to selected MBONs",
        },
        "neuronCount": len(nodes),
        "kenyonCellCount": len(kenyon_ids),
        "edgeCount": len(edges),
        "populationCounts": dict(sorted(population_counts.items())),
        "pathwayEdgeCounts": dict(sorted(pathway_edge_counts.items())),
        "pathwaySynapseCounts": dict(sorted(pathway_synapses.items())),
        "nodes": nodes,
        "edges": edges,
    }

    kenyon_rows = [by_body[body_id] for body_id in kenyon_ids]
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    SWIFT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    JSON_OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    SWIFT_OUTPUT.write_text(
        build_swift(
            kenyon_rows,
            forward_pn_to_kc,
            forward_kc_to_mbon,
            type_by_body,
            source_hashes,
            dict(population_counts),
            dict(pathway_synapses),
        ),
        encoding="utf-8",
    )

    print(
        json.dumps(
            {
                "dataset": DATASET_ID,
                "circuit": CIRCUIT_ID,
                "neurons": len(nodes),
                "kenyonCells": len(kenyon_ids),
                "edges": len(edges),
                "pathwayEdgeCounts": dict(sorted(pathway_edge_counts.items())),
                "pathwaySynapseCounts": dict(sorted(pathway_synapses.items())),
                "json": str(JSON_OUTPUT.relative_to(PROJECT_ROOT)),
                "swift": str(SWIFT_OUTPUT.relative_to(PROJECT_ROOT)),
                "sourceSHA256": source_hashes,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
