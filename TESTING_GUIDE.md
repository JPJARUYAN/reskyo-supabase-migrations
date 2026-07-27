# PHASE 9 — Testing Guide

## Test Results Summary

### Automated Tests ✅

| Test Suite | Tests | Status | Location |
|-----------|-------|--------|----------|
| SQL: haversine_km | 5 | ✅ ALL PASS | `tests/test_haversine.sql` |
| Dart: enums + constants | 15 | ✅ ALL PASS | `test/unit_test.dart` |
| Dart: widget tests | 7 | ✅ ALL PASS | `test/widget_test.dart` |
| Deno: compute-route haversine | 7 | ✅ ALL PASS | `supabase/functions/compute-route/compute-route_test.ts` |
| Deno: send-sms logic | 7 | ✅ ALL PASS | `supabase/functions/send-sms/send-sms_test.ts` |
| Deno: send-push logic | 3 | ✅ ALL PASS | `supabase/functions/send-push/send-push_test.ts` |
| Flutter: integration test scaffold | 5 | ✅ PASS | `integration_test/full_flow_test.dart` |

**Total: 49 automated tests passing**

### SQL Tests That Need Local Stack

These tests involve triggers that call Edge Functions via HTTP, which times out on the hosted Supabase. Run locally:

```bash
supabase start
supabase db query --local --file tests/test_sync_status.sql
supabase db query --local --file tests/test_match_responders.sql
```

---

## Running Tests

### SQL Tests (haversine — works on hosted)
```bash
supabase db query --linked --file tests/test_haversine.sql
```

### Dart Unit + Widget Tests
```bash
cd reskyo_finale
flutter test test/unit_test.dart
flutter test test/widget_test.dart
```

### Dart Integration Test (requires device/emulator)
```bash
cd reskyo_finale
flutter test integration_test/full_flow_test.dart
```

### Deno Edge Function Tests
```bash
cd supabase_migration
deno test supabase/functions/compute-route/compute-route_test.ts
deno test supabase/functions/send-sms/send-sms_test.ts
deno test supabase/functions/send-push/send-push_test.ts
```

---

## Manual / Field Tests (Chapter IV/V)

### 4. Field / User Acceptance Testing (UAT)

**Participants:** 2-3 CDRRMO staff + 3-5 volunteer responders + 5 resident testers

**Scenario Script:**
1. **Resident** opens app → taps "Report Emergency" → selects type → takes photo → submits
2. **Admin** logs into web dashboard → sees new incident on Live Map → clicks "Verify"
3. **Admin** clicks "Dispatch" → selects responder → confirm
4. **Responder** receives SMS on phone + push notification in app
5. **Responder** taps "Accept" → app shows A* route to incident
6. **Responder** taps "En Route" → status updates on dashboard in real-time
7. **Responder** taps "On Scene" → status updates
8. **Responder** taps "Resolved" → incident marked resolved on dashboard

**Document:**
- Screenshots of each step (phone + dashboard)
- Time from report submission to responder notification (target: <10 seconds)
- Participant feedback forms (1-5 scale + comments)

### 5. GPS Accuracy Testing

**Locations to test:**
- Digos City Plaza (urban center) — should be accurate within 5-10m
- Magsaysay residential area — should be accurate within 10-20m
- Dacudao outskirts — may have 20-50m inaccuracy
- Mountainous areas near Damires — may lose GPS signal

**Record:**
| Location | Expected Accuracy | Actual Accuracy | Notes |
|----------|------------------|-----------------|-------|
| City Plaza | 5-10m | ___m | |
| Magsaysay | 10-20m | ___m | |
| Dacudao | 20-50m | ___m | |
| Damires | 50m+ | ___m | |

### 6. Routing Accuracy Testing

**Compare A\* routes vs Google Maps for 3-5 sample trips:**

| Trip | A* Distance | Google Distance | A* ETA | Google ETA | Gap |
|------|-------------|-----------------|--------|------------|-----|
| City Plaza → Mati | ___km | ___km | ___min | ___min | ___% |
| Magsaysay → Goma | ___km | ___km | ___min | ___min | ___% |
| Dawis → Kiblawan | ___km | ___km | ___min | ___min | ___% |

**Note:** Gaps are expected because the A\* uses OSM road data which may be incomplete for some Digos City roads.

### 7. Load Testing

**Simulate 5-10 simultaneous incident reports:**
1. Open the app on 5 different phones (or emulators)
2. All reporters submit incidents within the same 30-second window
3. Check: no race conditions in responder matching
4. Check: all incidents get dispatched correctly
5. Check: no duplicate dispatches

**Record:**
- Total incidents created: ___
- Total dispatches created: ___
- Any errors or failures: ___
- Average time to dispatch: ___ seconds
