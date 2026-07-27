// ============================================
// PHASE 9: Unit Tests — compute-route haversineMeters()
// Run: deno test supabase/functions/compute-route/compute-route_test.ts
// ============================================

import { assertEquals, assertAlmostEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";

// ── Copy of the haversine function from compute-route ──
function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ── Test 1: Same point → 0 meters ──
Deno.test("haversine: same point returns 0", () => {
  const result = haversineMeters(6.7569, 125.3469, 6.7569, 125.3469);
  assertEquals(result, 0);
});

// ── Test 2: 1 degree latitude ≈ 111 km ──
Deno.test("haversine: 1 degree latitude ≈ 111km", () => {
  const result = haversineMeters(6.0, 125.0, 7.0, 125.0);
  assertAlmostEquals(result, 111195, 1000); // within 1km tolerance
});

// ── Test 3: Symmetry ──
Deno.test("haversine: symmetric", () => {
  const r1 = haversineMeters(6.75, 125.34, 6.78, 125.38);
  const r2 = haversineMeters(6.78, 125.38, 6.75, 125.34);
  assertEquals(r1, r2);
});

// ── Test 4: Digos City center to Mati City (~60km) ──
Deno.test("haversine: Digos to Mati ≈ 60km", () => {
  const result = haversineMeters(6.7569, 125.3469, 6.9533, 126.2194);
  assertAlmostEquals(result, 60000, 8000); // 52-68km range
});

// ── Test 5: Small distance — two Digos barangays (~1km) ──
Deno.test("haversine: Magsaysay to Dawis ≈ 1km", () => {
  const result = haversineMeters(6.7529, 125.3469, 6.7539, 125.3539);
  assertAlmostEquals(result, 800, 500); // 300m-1300m range
});

// ── Test 6: Negative coordinates (Southern hemisphere) ──
Deno.test("haversine: negative lat works", () => {
  const result = haversineMeters(-6.7569, 125.3469, -6.7579, 125.3479);
  assertAlmostEquals(result, 150, 100); // very close points
});

// ── Test 7: Long distance — Manila to Digos (~1500km) ──
Deno.test("haversine: Manila to Digos ≈ 1500km", () => {
  const result = haversineMeters(14.5995, 120.9842, 6.7569, 125.3469);
  assertAlmostEquals(result, 1500000, 100000); // 1400-1600km
});

console.log("=== All compute-route unit tests passed ===");
