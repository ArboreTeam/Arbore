# P1 validation on physical devices

This checklist covers what a simulator cannot validate: camera, LiDAR, RoomPlan,
ARKit, real location, and thermal behaviour. A blank result means “not tested”
and must never be reported as a pass.

## Minimum device pool

Test at least two iPhones on an app-supported iOS version (current deployment
target: iOS 18.2):

| Profile | Example | Purpose |
|---|---|---|
| LiDAR iPhone | iPhone 12 Pro or a newer Pro | RoomPlan, depth, room scan |
| Non-LiDAR iPhone | standard iPhone 12/13/14/15/16 or 16e | guided tracing, plane detection, baseline performance |
| Oldest supported device available, recommended | oldest real device in the pool | realistic memory, battery, and thermal worst case |

Use a clean Release/TestFlight build. Record device model, iOS version, Arbore
version, and build number before each session.

## Required scenarios

### 1. Permissions and location

1. Install with no pre-existing permissions.
2. Create a room, a balcony/terrace, and a garden in turn.
3. Confirm that camera permission is requested at scan time, not at launch.
4. After scanning, confirm that each new garden requests location again or lets
   the user enter a city; also test approximate location.
5. Deny camera and then location, recover through Settings, and resume without a
   blocked screen or lost draft.

Pass: no exact address is displayed or retained; city, orientation, and sunlight
reach the 2D plan.

### 2. LiDAR room / RoomPlan

1. Measure a simple room and a room with a door, window, and furniture using a
   tape measure.
2. Run RoomPlan, then point the phone at the requested light source.
3. Compare width, length, and area with the manual measurements.
4. Open AR; place, move, and delete three plants; leave and reopen the garden.

Target: dimension error below 5% or 10 cm on a simple length; no crash; objects
remain in the expected area after reopening. Any error above 10% is blocking or
must be clearly offered for manual correction.

### 3. Non-LiDAR space

1. Trace four corners normally, then deliberately choose an order that used to
   produce crossing diagonals.
2. Test a narrow balcony, a terrace, and a non-rectangular garden outline.
3. Redo the dimensions from the 2D plan.

Pass: points are easy to place and undo, the contour never self-intersects,
closure is understandable, and edits reach the 2D plan.

### 4. Catalogue and network

1. Clear thumbnail cache, then open the catalogue on Wi-Fi and cellular data.
2. Scroll through all 124 plants, search, and combine several filters.
3. Open ten plants and place at least five AR models.

Pass: cards download server PNGs without local USDZ reconstruction, simple
scrolling does not cause a thermal spike, no thumbnail is white or cropped, and
a network failure shows a fallback with a working retry.

### 5. Thermal session

On each device profile, run a continuous 20-minute session: 5 minutes scanning,
10 minutes placing/moving in AR, and 5 minutes in the catalogue. Every 5 minutes,
record logged thermal state, battery, responsiveness, and any Arbore warning.

Pass: no crash or lock-up; at `.serious`/`.critical`, AR quality degrades through
the adaptive controller; catalogue browsing never rebuilds thumbnails. An iOS
termination caused by memory pressure or heat is blocking.

## Results sheet

| Date | Device / iOS | Build | LiDAR room | Non-LiDAR | Location | Catalogue | 20-min thermal | Issues |
|---|---|---|---|---|---|---|---|---|
| To fill in |  |  |  |  |  |  |  |  |

Attach screenshots, videos, and Sentry logs to each issue. App Store readiness
can only be marked as validated when both minimum profiles have every required
column completed with no blocking issue.
