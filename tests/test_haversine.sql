-- ============================================
-- PHASE 9: Unit Tests — haversine_km()
-- Returns test results as rows
-- ============================================
SELECT 'test1: same point = 0' AS test,
  CASE WHEN haversine_km(6.7569, 125.3469, 6.7569, 125.3469) = 0.0
    THEN 'PASS' ELSE 'FAIL' END AS result,
  haversine_km(6.7569, 125.3469, 6.7569, 125.3469) AS actual_km
UNION ALL
SELECT 'test2: Digos→Mati ≈ 99km',
  CASE WHEN haversine_km(6.7569, 125.3469, 6.9533, 126.2194) BETWEEN 90 AND 110
    THEN 'PASS' ELSE 'FAIL' END,
  round(haversine_km(6.7569, 125.3469, 6.9533, 126.2194)::numeric, 1)
UNION ALL
SELECT 'test3: 1deg latitude ≈ 111km',
  CASE WHEN haversine_km(6.0, 125.0, 7.0, 125.0) BETWEEN 105 AND 117
    THEN 'PASS' ELSE 'FAIL' END,
  round(haversine_km(6.0, 125.0, 7.0, 125.0)::numeric, 1)
UNION ALL
SELECT 'test4: symmetry A→B = B→A',
  CASE WHEN abs(haversine_km(6.75, 125.34, 6.78, 125.38) - haversine_km(6.78, 125.38, 6.75, 125.34)) < 0.001
    THEN 'PASS' ELSE 'FAIL' END,
  round(haversine_km(6.75, 125.34, 6.78, 125.38)::numeric, 3)
UNION ALL
SELECT 'test5: Magsaysay→Dawis ≈ 1km',
  CASE WHEN haversine_km(6.7529, 125.3469, 6.7539, 125.3539) BETWEEN 0.5 AND 3.0
    THEN 'PASS' ELSE 'FAIL' END,
  round(haversine_km(6.7529, 125.3469, 6.7539, 125.3539)::numeric, 3);