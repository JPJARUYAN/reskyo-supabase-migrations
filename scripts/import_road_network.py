#!/usr/bin/env python3
"""
PHASE 4: Import Digos City road network from OpenStreetMap
into Supabase road_nodes / road_edges tables.

Prerequisites:
  pip install osmnx shapely psycopg2-binary

Usage:
  python import_road_network.py

This script:
1. Downloads OSM road data for Digos City bounding box
2. Extracts intersections as nodes, road segments as edges
3. Computes Haversine distance for each edge
4. Inserts into Supabase via PostgreSQL
"""

import math
import osmnx as ox
import psycopg2
from psycopg2.extras import execute_values

# ============================================
# CONFIG - Replace with your Supabase credentials
# ============================================
SUPABASE_HOST = "db.iurepkmnnyrxuqqzmfvy.supabase.co"
SUPABASE_PORT = 5432
SUPABASE_DB = "postgres"
SUPABASE_USER = "postgres"
SUPABASE_PASSWORD = "YOUR_DB_PASSWORD"  # Get from Supabase → Settings → Database

# Digos City bounding box (approximate)
# Format: (north, south, east, west)
DIGOS_bbox = (6.80, 6.70, 125.40, 125.30)


def haversine_meters(lat1, lng1, lat2, lng2):
    """Compute distance in meters between two lat/lng points."""
    R = 6371000  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def download_road_network():
    """Download OSM road network for Digos City."""
    print("Downloading road network for Digos City...")
    north, south, east, west = DIGOS_bbox

    # Get road network - includes highways, secondary, tertiary, residential
    G = ox.graph_from_bbox(
        bbox=(east, west, north, south),
        network_type="drive",
        simplify=True,
    )

    print(f"Downloaded: {len(G.nodes)} nodes, {len(G.edges)} edges")
    return G


def extract_nodes_and_edges(G):
    """Convert OSMnx graph to our node/edge format."""
    nodes = []
    node_id_map = {}  # osmid -> our sequential id
    edges = []
    node_counter = 1

    # Extract nodes
    for osmid, data in G.nodes(data=True):
        node_id_map[osmid] = node_counter
        nodes.append({
            "id": node_counter,
            "osmid": osmid,
            "latitude": data["y"],
            "longitude": data["x"],
            "node_type": "intersection",
            "label": None,
        })
        node_counter += 1

    # Extract edges
    edge_counter = 1
    for u, v, data in G.edges(data=True):
        # Get coordinates for distance calculation
        u_data = G.nodes[u]
        v_data = G.nodes[v]

        distance = haversine_meters(u_data["y"], u_data["x"], v_data["y"], v_data["x"])

        # Get road name if available
        road_name = data.get("name", None)
        if isinstance(road_name, list):
            road_name = road_name[0] if road_name else None

        edges.append({
            "id": edge_counter,
            "from_node": node_id_map[u],
            "to_node": node_id_map[v],
            "distance_meters": round(distance, 2),
            "road_name": road_name,
            "is_paved": data.get("surface", "paved") not in ("unpaved", "dirt", "gravel"),
            "weight": 1.0,
        })
        edge_counter += 1

    # Add bidirectional edges (roads go both ways unless oneway)
    bidirectional_edges = list(edges)
    for u, v, data in G.edges(data=True):
        if not data.get("oneway", False):
            u_data = G.nodes[u]
            v_data = G.nodes[v]
            distance = haversine_meters(u_data["y"], u_data["x"], v_data["y"], v_data["x"])
            road_name = data.get("name", None)
            if isinstance(road_name, list):
                road_name = road_name[0] if road_name else None

            bidirectional_edges.append({
                "id": edge_counter,
                "from_node": node_id_map[v],
                "to_node": node_id_map[u],
                "distance_meters": round(distance, 2),
                "road_name": road_name,
                "is_paved": data.get("surface", "paved") not in ("unpaved", "dirt", "gravel"),
                "weight": 1.0,
            })
            edge_counter += 1

    print(f"Extracted {len(nodes)} nodes, {len(bidirectional_edges)} edges (bidirectional)")
    return nodes, bidirectional_edges


def import_to_database(nodes, edges):
    """Insert nodes and edges into Supabase PostgreSQL."""
    print("Connecting to Supabase database...")

    conn = psycopg2.connect(
        host=SUPABASE_HOST,
        port=SUPABASE_PORT,
        dbname=SUPABASE_DB,
        user=SUPABASE_USER,
        password=SUPABASE_PASSWORD,
        sslmode="require",
    )
    cur = conn.cursor()

    try:
        # Clear existing data
        print("Clearing existing road data...")
        cur.execute("DELETE FROM road_edges")
        cur.execute("DELETE FROM road_nodes")

        # Reset sequences
        cur.execute("ALTER SEQUENCE road_nodes_id_seq RESTART WITH 1")
        cur.execute("ALTER SEQUENCE road_edges_id_seq RESTART WITH 1")

        # Insert nodes
        print(f"Inserting {len(nodes)} nodes...")
        node_values = [
            (n["latitude"], n["longitude"], n["node_type"], n["label"])
            for n in nodes
        ]
        execute_values(
            cur,
            "INSERT INTO road_nodes (latitude, longitude, node_type, label) VALUES %s",
            node_values,
            page_size=1000,
        )

        # Get the auto-generated IDs (PostgreSQL will assign them)
        cur.execute("SELECT id FROM road_nodes ORDER BY id")
        db_node_ids = [row[0] for row in cur.fetchall()]

        # We need to map our sequential IDs to the database IDs
        # Since we reset the sequence, they should match 1:1
        id_offset = db_node_ids[0] - 1 if db_node_ids else 0

        # Insert edges with corrected node references
        print(f"Inserting {len(edges)} edges...")
        edge_values = [
            (
                e["from_node"] + id_offset,
                e["to_node"] + id_offset,
                e["distance_meters"],
                e["road_name"],
                e["is_paved"],
                e["weight"],
            )
            for e in edges
        ]
        execute_values(
            cur,
            """INSERT INTO road_edges (from_node, to_node, distance_meters, road_name, is_paved, weight)
               VALUES %s""",
            edge_values,
            page_size=1000,
        )

        conn.commit()
        print("Import complete!")

        # Print summary
        cur.execute("SELECT COUNT(*) FROM road_nodes")
        node_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM road_edges")
        edge_count = cur.fetchone()[0]
        print(f"Database now has: {node_count} nodes, {edge_count} edges")

    except Exception as e:
        conn.rollback()
        print(f"Error: {e}")
        raise
    finally:
        cur.close()
        conn.close()


def main():
    print("=" * 60)
    print("RESKYO Road Network Importer - Digos City")
    print("=" * 60)

    # Download from OSM
    G = download_road_network()

    # Convert to our format
    nodes, edges = extract_nodes_and_edges(G)

    # Import to database
    import_to_database(nodes, edges)

    print("=" * 60)
    print("Done! Road network loaded into Supabase.")
    print("=" * 60)


if __name__ == "__main__":
    main()
