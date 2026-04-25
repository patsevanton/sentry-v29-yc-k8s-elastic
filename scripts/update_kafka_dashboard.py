import json
import copy

src_path = "/home/user/github/patsevanton/sentry-v29-yc-k8s-elastic/dashboard/yc-managed-kafka-overview.json"
with open(src_path, "r", encoding="utf-8") as f:
    data = json.load(f)

existing = data["panels"]
base_id = max(p["id"] for p in existing)


def next_id():
    global base_id
    base_id += 1
    return base_id


DS = {"type": "prometheus", "uid": "${DS_PROMETHEUS}"}


def make_stat(title, expr, gridPos, thresholds, unit="none", legend="value"):
    return {
        "datasource": copy.deepcopy(DS),
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "thresholds": {"mode": "absolute", "steps": thresholds},
                **({"unit": unit} if unit != "none" else {}),
            },
            "overrides": [],
        },
        "gridPos": dict(gridPos),
        "id": next_id(),
        "options": {
            "colorMode": "background",
            "graphMode": "none",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {
                "calcs": ["lastNotNull"],
                "fields": "",
                "values": False,
            },
            "textMode": "value",
        },
        "targets": [
            {
                "editorMode": "code",
                "expr": expr,
                "legendFormat": legend,
                "range": True,
                "refId": "A",
            }
        ],
        "title": title,
        "type": "stat",
    }


def make_timeseries(title, targets, gridPos, unit="none"):
    defaults = {
        "custom": {
            "drawStyle": "line",
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 4,
            "showPoints": "never",
            "spanNulls": False,
        }
    }
    if unit != "none":
        defaults["unit"] = unit
    return {
        "datasource": copy.deepcopy(DS),
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "gridPos": dict(gridPos),
        "id": next_id(),
        "options": {
            "legend": {
                "calcs": [],
                "displayMode": "list",
                "placement": "bottom",
                "showLegend": True,
            },
            "tooltip": {"mode": "single", "sort": "none"},
        },
        "targets": [
            {
                "editorMode": "code",
                "expr": t["expr"],
                "legendFormat": t.get("legendFormat", ""),
                "range": True,
                "refId": chr(65 + i),
            }
            for i, t in enumerate(targets)
        ],
        "title": title,
        "type": "timeseries",
    }


new_panels = []

# Row 4 (y=29, h=5) - stats
new_panels.append(
    make_stat(
        "Active controllers",
        "sum(kafka_controller_KafkaController_ActiveControllerCount{resource_id=~\"$cluster\",host=~\"$host\"})",
        {"h": 5, "w": 6, "x": 6, "y": 29},
        [{"color": "red", "value": None}, {"color": "green", "value": 1}],
        legend="active",
    )
)

new_panels.append(
    make_stat(
        "Reassigning partitions",
        "sum(kafka_server_ReplicaManager_ReassigningPartitions{resource_id=~\"$cluster\",host=~\"$host\"})",
        {"h": 5, "w": 6, "x": 18, "y": 29},
        [
            {"color": "green", "value": None},
            {"color": "yellow", "value": 1},
            {"color": "red", "value": 5},
        ],
        legend="reassigning",
    )
)

# Row 5 (y=34, h=8) - timeseries x2
new_panels.append(
    make_timeseries(
        "Partitions & Leaders",
        [
            {
                "expr": "sum by (host) (kafka_server_ReplicaManager_PartitionCount{resource_id=~\"$cluster\",host=~\"$host\"})",
                "legendFormat": "{{host}} partitions",
            },
            {
                "expr": "sum by (host) (kafka_server_ReplicaManager_LeaderCount{resource_id=~\"$cluster\",host=~\"$host\"})",
                "legendFormat": "{{host}} leaders",
            },
        ],
        {"h": 8, "w": 12, "x": 12, "y": 34},
        unit="short",
    )
)

new_panels.append(
    make_timeseries(
        "Request rate by type",
        [
            {
                "expr": "sum by (request) (rate(kafka_network_RequestMetrics_Requests{resource_id=~\"$cluster\",host=~\"$host\",request=~\"$request\"}[5m]))",
                "legendFormat": "{{request}}",
            }
        ],
        {"h": 8, "w": 12, "x": 0, "y": 50},
        unit="reqps",
    )
)

new_panels.append(
    make_timeseries(
        "Request errors by type",
        [
            {
                "expr": "sum by (request) (rate(kafka_network_RequestMetrics_Errors{resource_id=~\"$cluster\",host=~\"$host\",request=~\"$request\"}[5m]))",
                "legendFormat": "{{request}}",
            }
        ],
        {"h": 8, "w": 12, "x": 12, "y": 50},
        unit="reqps",
    )
)

# Row 6 (y=58, h=8)
new_panels.append(
    make_timeseries(
        "CPU breakdown %",
        [
            {
                "expr": "avg by (host) (100 - cpu_idle{resource_id=~\"$cluster\",host=~\"$host\"})",
                "legendFormat": "{{host}} used",
            },
            {
                "expr": "avg by (host) (cpu_iowait{resource_id=~\"$cluster\",host=~\"$host\"})",
                "legendFormat": "{{host}} iowait",
            },
            {
                "expr": "avg by (host) (cpu_system{resource_id=~\"$cluster\",host=~\"$host\"})",
                "legendFormat": "{{host}} system",
            },
            {
                "expr": "avg by (host) (cpu_user{resource_id=~\"$cluster\",host=~\"$host\"})",
                "legendFormat": "{{host}} user",
            },
        ],
        {"h": 8, "w": 12, "x": 0, "y": 66},
        unit="percent",
    )
)

new_panels.append(
    make_timeseries(
        "Produce / Fetch latency p99",
        [
            {
                "expr": "max by (host) (kafka_network_RequestMetrics_TotalTimeMs{resource_id=~\"$cluster\",host=~\"$host\",request=\"Produce\",quantile=\"0.99\"})",
                "legendFormat": "Produce",
            },
            {
                "expr": "max by (host) (kafka_network_RequestMetrics_TotalTimeMs{resource_id=~\"$cluster\",host=~\"$host\",request=\"Fetch\",quantile=\"0.99\"})",
                "legendFormat": "Fetch",
            },
        ],
        {"h": 8, "w": 12, "x": 12, "y": 66},
        unit="ms",
    )
)

# Update data
existing.extend(new_panels)
data["panels"] = existing

with open(src_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"Done. Total panels: {len(existing)}")
