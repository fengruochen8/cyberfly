#!/usr/bin/env python3
"""Compile the traced MaleCNS v1.0 connectome into an exact binary CSR/CSC graph.

The compiler deliberately keeps the biological observations separate from runtime
model assumptions. Nodes and summed body-to-body synapse counts are lossless;
transmitter identities remain predictions and are encoded without assigning a
physiological sign in this file format.
"""

from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import time
from typing import Iterable

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.feather as feather


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = PROJECT_ROOT / "Data" / "raw"
OUTPUT_DIR = (
    PROJECT_ROOT
    / "Sources"
    / "CyberFlySimulation"
    / "Resources"
    / "FullCNS"
)

ANNOTATIONS = RAW_DIR / "body-annotations-male-cns-v1.0-minconf-0.5.feather"
NEUROTRANSMITTERS = RAW_DIR / "body-neurotransmitters-male-cns-v1.0.feather"
WEIGHTS = RAW_DIR / "connectome-weights-male-cns-v1.0-minconf-0.5.feather"
SOURCE_MANIFEST = PROJECT_ROOT / "Data" / "manifests" / "male-cns-v1.0.json"

DATASET_ID = "male-cns:v1.0"
FORMAT_ID = "cyberfly-full-cns-v1"
NODE_RECORD = struct.Struct("<QIBBBBiiif")
MISSING_COORDINATE = -(2**31)

ROLE_BITS = {
    "sensory": 1 << 0,
    "motor": 1 << 1,
    "descending": 1 << 2,
    "ascending": 1 << 3,
    "visual": 1 << 4,
    "olfactory": 1 << 5,
    "gustatory": 1 << 6,
    "mechanosensory": 1 << 7,
    "central_complex": 1 << 8,
    "mushroom_body": 1 << 9,
    "dopaminergic": 1 << 10,
    "neurosecretory": 1 << 11,
    "sex_specific": 1 << 12,
}

TRANSMITTER_CODES = {
    "unclear": 0,
    "acetylcholine": 1,
    "gaba": 2,
    "glutamate": 3,
    "dopamine": 4,
    "serotonin": 5,
    "octopamine": 6,
    "histamine": 7,
}


def sha256(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def source_hashes() -> dict[str, str]:
    if SOURCE_MANIFEST.exists():
        manifest = json.loads(SOURCE_MANIFEST.read_text())
        return {
            source["kind"]: source["sha256"]
            for source in manifest.get("sources", [])
        }
    return {
        "annotations": sha256(ANNOTATIONS),
        "neurotransmitters": sha256(NEUROTRANSMITTERS),
        "connectome-weights": sha256(WEIGHTS),
    }


def annotation_text(row: dict[str, object]) -> str:
    fields = (
        "superclass",
        "class",
        "subclass",
        "type",
        "instance",
        "flywireType",
        "hemibrainType",
        "entryNerve",
        "exitNerve",
        "receptorType",
        "fruDsx",
    )
    return " ".join(str(row.get(field) or "").lower() for field in fields)


def role_flags(row: dict[str, object], transmitter: str) -> int:
    text = annotation_text(row)
    superclass = str(row.get("superclass") or "").lower()
    cell_class = str(row.get("class") or "").lower()
    flags = 0

    def mark(role: str, *terms: str) -> None:
        nonlocal flags
        if any(term in text for term in terms):
            flags |= ROLE_BITS[role]

    mark("sensory", "sensory", "receptor", "orn", "brp", "grn", "thermo", "hygro")
    mark("motor", "motor_neuron", "motor neuron", "motoneuron")
    mark("descending", "descending_neuron", "descending neuron", " dnp", " dng", "dnp", "dng")
    mark("ascending", "ascending_neuron", "ascending neuron", "an_", " ascending")
    mark("visual", "visual", "optic", "lop", "medulla", "lamina", "ocellar", "photoreceptor")
    mark("olfactory", "olfactory", "antennal lobe", "orn", " dm1", " dm2")
    mark("gustatory", "gustatory", "taste", "grn")
    mark("mechanosensory", "mechanosensory", "chordotonal", "campaniform", "bristle")
    mark("central_complex", "central_complex", "central complex", "protocerebral_bridge")
    mark("mushroom_body", "mushroom_body", "mushroom body", "kenyon", "mbon", " kc")
    mark("neurosecretory", "neurosecretory", "pars intercerebralis")
    mark("sex_specific", "fru", "dsx", "sex-specific", "sex specific")
    if "sensory" in superclass:
        flags |= ROLE_BITS["sensory"]
    if "motor" in superclass:
        flags |= ROLE_BITS["motor"]
    if superclass.startswith("ol_") or superclass.startswith("visual_"):
        flags |= ROLE_BITS["visual"]
    if cell_class in {"olfactory", "alpn", "alln", "alin", "alon"}:
        flags |= ROLE_BITS["olfactory"]
    if cell_class == "cx":
        flags |= ROLE_BITS["central_complex"]
    if cell_class in {"kenyon_cell", "mbon"}:
        flags |= ROLE_BITS["mushroom_body"]
    if "endocrine" in superclass:
        flags |= ROLE_BITS["neurosecretory"]
    if transmitter == "dopamine":
        flags |= ROLE_BITS["dopaminergic"]
    return flags


def hemisphere_code(row: dict[str, object]) -> int:
    side = str(row.get("somaSide") or row.get("rootSide") or "").upper()
    if side.startswith("L"):
        return 1
    if side.startswith("R"):
        return 2
    if side.startswith("M") or "MID" in side:
        return 3
    return 0


def quality_code(row: dict[str, object]) -> int:
    label = str(row.get("statusLabel") or "").lower()
    if "traced" not in label:
        return 0
    if "prelim" in label:
        return 1
    if "roughly" in label:
        return 2
    return 3


def soma_coordinates(row: dict[str, object]) -> tuple[int, int, int]:
    value = row.get("somaLocation") or row.get("tosomaLocation")
    if not isinstance(value, list) or len(value) != 3:
        return (MISSING_COORDINATE,) * 3
    return tuple(int(component) for component in value)  # type: ignore[return-value]


def load_transmitters(traced_ids: set[int]) -> dict[int, tuple[str, float]]:
    table = feather.read_table(
        NEUROTRANSMITTERS,
        columns=["body", "consensus_nt", "predicted_nt_confidence"],
        memory_map=True,
    )
    result: dict[int, tuple[str, float]] = {}
    for batch in table.to_batches(max_chunksize=100_000):
        bodies = batch.column(batch.schema.get_field_index("body")).to_pylist()
        transmitters = batch.column(batch.schema.get_field_index("consensus_nt")).to_pylist()
        confidences = batch.column(
            batch.schema.get_field_index("predicted_nt_confidence")
        ).to_pylist()
        for body, raw_nt, raw_confidence in zip(bodies, transmitters, confidences):
            body_id = int(body)
            if body_id not in traced_ids:
                continue
            transmitter = str(raw_nt or "unclear").lower()
            confidence = float(raw_confidence or 0)
            previous = result.get(body_id)
            # Prefer an identified transmitter over "unclear", then retain the
            # strongest prediction for repeated body rows.
            rank = (transmitter != "unclear", confidence)
            previous_rank = (
                previous is not None and previous[0] != "unclear",
                previous[1] if previous is not None else -1,
            )
            if previous is None or rank > previous_rank:
                result[body_id] = (transmitter, confidence)
    return result


def write_bytes_atomically(path: Path, chunks: Iterable[bytes | memoryview]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("wb") as handle:
        for chunk in chunks:
            handle.write(chunk)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def write_arrow_values(path: Path, column: pa.ChunkedArray, target_type: pa.DataType) -> None:
    values = pc.cast(column, target_type).combine_chunks()
    if values.null_count:
        raise ValueError(f"{path.name} contains null values")
    buffer = values.buffers()[1]
    if buffer is None:
        raise ValueError(f"{path.name} has no values buffer")
    write_bytes_atomically(path, [memoryview(buffer)])


def build_offsets(sorted_indices: pa.ChunkedArray, node_count: int) -> array:
    encoded = pc.run_end_encode(sorted_indices.combine_chunks())
    run_ends = encoded.run_ends.to_pylist()
    run_values = encoded.values.to_pylist()
    offsets = array("Q", [0]) * (node_count + 1)
    previous_end = 0
    next_node = 0
    for raw_index, raw_end in zip(run_values, run_ends):
        index = int(raw_index)
        end = int(raw_end)
        for missing in range(next_node, index):
            offsets[missing + 1] = previous_end
        offsets[index + 1] = end
        previous_end = end
        next_node = index + 1
    for missing in range(next_node, node_count):
        offsets[missing + 1] = previous_end
    return offsets


def file_record(path: Path) -> dict[str, object]:
    return {
        "name": path.name,
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def compile_graph(output_dir: Path) -> dict[str, object]:
    if sys.byteorder != "little":
        raise RuntimeError("The v1 graph format requires a little-endian compiler host")
    for required in (ANNOTATIONS, NEUROTRANSMITTERS, WEIGHTS):
        if not required.exists():
            raise FileNotFoundError(f"Missing official MaleCNS source: {required}")
    output_dir.mkdir(parents=True, exist_ok=True)

    started = time.perf_counter()
    annotation_columns = [
        "bodyId",
        "status",
        "statusLabel",
        "superclass",
        "class",
        "subclass",
        "type",
        "instance",
        "flywireType",
        "hemibrainType",
        "entryNerve",
        "exitNerve",
        "receptorType",
        "fruDsx",
        "somaSide",
        "rootSide",
        "somaLocation",
        "tosomaLocation",
    ]
    annotations = feather.read_table(
        ANNOTATIONS,
        columns=annotation_columns,
        memory_map=True,
    )
    annotations = annotations.filter(pc.equal(annotations["status"], "Traced"))
    annotations = annotations.take(pc.sort_indices(annotations, sort_keys=[("bodyId", "ascending")]))
    node_ids = annotations["bodyId"].combine_chunks()
    node_count = annotations.num_rows
    traced_ids = {int(value) for value in node_ids.to_pylist()}
    if len(traced_ids) != node_count:
        raise ValueError("Traced annotation body IDs are not unique")

    transmitters = load_transmitters(traced_ids)
    role_counts = {name: 0 for name in ROLE_BITS}
    transmitter_counts = {name: 0 for name in TRANSMITTER_CODES}
    nodes_path = output_dir / "nodes.bin"
    node_temporary = nodes_path.with_suffix(".bin.tmp")
    with node_temporary.open("wb") as handle:
        for batch in annotations.to_batches(max_chunksize=20_000):
            for row in batch.to_pylist():
                body_id = int(row["bodyId"])
                transmitter, confidence = transmitters.get(body_id, ("unclear", 0))
                if transmitter not in TRANSMITTER_CODES:
                    transmitter = "unclear"
                flags = role_flags(row, transmitter)
                for name, bit in ROLE_BITS.items():
                    if flags & bit:
                        role_counts[name] += 1
                transmitter_counts[transmitter] += 1
                x, y, z = soma_coordinates(row)
                handle.write(
                    NODE_RECORD.pack(
                        body_id,
                        flags,
                        TRANSMITTER_CODES[transmitter],
                        hemisphere_code(row),
                        quality_code(row),
                        0,
                        x,
                        y,
                        z,
                        confidence,
                    )
                )
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(node_temporary, nodes_path)

    print(f"Loaded {node_count:,} traced nodes; aggregating weights...", flush=True)
    weights = feather.read_table(WEIGHTS, memory_map=True)
    source_row_count = weights.num_rows
    grouped = weights.group_by(["body_pre", "body_post"]).aggregate([("weight", "sum")])
    del weights

    pre_indices = pc.index_in(grouped["body_pre"], value_set=node_ids)
    post_indices = pc.index_in(grouped["body_post"], value_set=node_ids)
    included = pc.and_(pc.greater_equal(pre_indices, 0), pc.greater_equal(post_indices, 0))
    graph = pa.table(
        {
            "pre": pc.cast(pc.filter(pre_indices, included), pa.uint32()),
            "post": pc.cast(pc.filter(post_indices, included), pa.uint32()),
            "weight": pc.cast(pc.filter(grouped["weight_sum"], included), pa.uint32()),
        }
    )
    del grouped, pre_indices, post_indices, included

    edge_count = graph.num_rows
    synapse_weight_sum = int(pc.sum(graph["weight"]).as_py())
    maximum_edge_weight = int(pc.max(graph["weight"]).as_py())
    if edge_count >= 2**32:
        raise ValueError("Edge count exceeds the UInt32 node-index format")

    print(f"Writing CSR for {edge_count:,} edges...", flush=True)
    outgoing = graph.take(
        pc.sort_indices(graph, sort_keys=[("pre", "ascending"), ("post", "ascending")])
    )
    outgoing_offsets = build_offsets(outgoing["pre"], node_count)
    write_bytes_atomically(output_dir / "out-offsets.bin", [memoryview(outgoing_offsets)])
    write_arrow_values(output_dir / "out-targets.bin", outgoing["post"], pa.uint32())
    write_arrow_values(output_dir / "out-weights.bin", outgoing["weight"], pa.uint32())

    print("Writing CSC...", flush=True)
    incoming = graph.take(
        pc.sort_indices(graph, sort_keys=[("post", "ascending"), ("pre", "ascending")])
    )
    incoming_offsets = build_offsets(incoming["post"], node_count)
    write_bytes_atomically(output_dir / "in-offsets.bin", [memoryview(incoming_offsets)])
    write_arrow_values(output_dir / "in-sources.bin", incoming["pre"], pa.uint32())
    write_arrow_values(output_dir / "in-weights.bin", incoming["weight"], pa.uint32())

    output_paths = [
        nodes_path,
        output_dir / "out-offsets.bin",
        output_dir / "out-targets.bin",
        output_dir / "out-weights.bin",
        output_dir / "in-offsets.bin",
        output_dir / "in-sources.bin",
        output_dir / "in-weights.bin",
    ]
    graph_digest = hashlib.sha256()
    for path in output_paths:
        graph_digest.update(bytes.fromhex(sha256(path)))

    manifest: dict[str, object] = {
        "schemaVersion": 1,
        "format": FORMAT_ID,
        "dataset": DATASET_ID,
        "license": "CC-BY-4.0",
        "compiledAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "nodeRecordBytes": NODE_RECORD.size,
        "nodeCount": node_count,
        "edgeCount": edge_count,
        "sourceWeightRowCount": source_row_count,
        "synapseWeightSum": synapse_weight_sum,
        "maximumEdgeWeight": maximum_edge_weight,
        "graphSha256": graph_digest.hexdigest(),
        "nodeOrdering": "ascending bodyId",
        "edgeAggregation": "sum(weight) by body_pre/body_post, traced endpoints only",
        "outgoingOrdering": "pre node index, then post node index",
        "incomingOrdering": "post node index, then pre node index",
        "provenance": {
            "nodes": "observed",
            "edges": "observed",
            "weights": "observed synapse counts",
            "neurotransmitters": "predicted",
            "roles": "derived/fitted text classification from observed annotations",
            "dynamics": "not contained in this artifact",
        },
        "sourceSha256": source_hashes(),
        "roleBits": ROLE_BITS,
        "roleCounts": role_counts,
        "transmitterCodes": TRANSMITTER_CODES,
        "transmitterCounts": transmitter_counts,
        "files": [file_record(path) for path in output_paths],
        "compileSeconds": round(time.perf_counter() - started, 3),
    }
    manifest_path = output_dir / "manifest.json"
    temporary_manifest = manifest_path.with_suffix(".json.tmp")
    temporary_manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    os.replace(temporary_manifest, manifest_path)
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=OUTPUT_DIR,
        help="destination for manifest.json and binary arrays",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = compile_graph(args.output_dir.resolve())
    print(
        json.dumps(
            {
                "dataset": manifest["dataset"],
                "nodes": manifest["nodeCount"],
                "edges": manifest["edgeCount"],
                "synapses": manifest["synapseWeightSum"],
                "graphSha256": manifest["graphSha256"],
                "compileSeconds": manifest["compileSeconds"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
