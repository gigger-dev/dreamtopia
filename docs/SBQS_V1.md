Version 1.0 • 5 October 2026 • Draft for business and development review

This specification defines three account roles, class scheduling,
instructor availability, manual payment verification, package credits,
walk-in bookings and cancellations. It translates the supplied
requirements into implementable workflows and acceptance criteria.
Proposed defaults are identified separately and require business
approval before implementation.

# 1 Scope and terminology

| **Term** | **Meaning** |
|----|----|
| Class definition | Reusable class type with description, booking modes and pricing, such as Pole Beginner or Pilates. |
| Class session | A dated occurrence with start and end times, instructor, room and capacity. |
| Walk in | A single-session purchase. No package credits required; this also applies when reserved in the app. |
| Package | A purchased bundle such as 4 or 8 classes. Approved payment activates the associated credit balance. |
| Booking | One member enrollment in one session, with its payment or credit funding method recorded. |
| Credit | An entitlement to book an eligible class. Cost and eligibility belong to the class/package configuration. |

# 2 Role permissions

| **Action** | **Administrator** | **Member** | **Instructor** |
|----|----|----|----|
| Create classes and packages | Yes | No | No |
| Schedule, publish, update or cancel | Yes | No | No |
| Verify payment and enroll member | Yes | No | No |
| View calendar | All sessions | Published sessions | Own assignments |
| Book and view purchases or credits | On member behalf | Own account | No |
| Cancel member booking | Override with reason | Own, before cutoff | No |
| Set instructor availability | Manage with audit | No | Own calendar |
| Accept assignment or configure auto accept | Manage assignment | No | Own assignments |

Role checks must be enforced by the server. Members see only their own
purchases, payment proofs, credits and bookings. Instructors see their
own assignments and relevant session rosters, without access to member
payment proofs.

# 3 Functional requirements

| **ID** | **Requirement** |
|----|----|
| FR01 | Support Administrator, Member and Instructor accounts, authenticated access and role-based screens. |
| FR02 | Administrator creates and edits class definitions, supported booking modes, package eligibility, credit cost, walk-in price and package prices. |
| FR03 | Administrator schedules sessions with date, start/end time, room, capacity and instructor; publishes sessions on the member calendar. |
| FR04 | Administrator reviews submitted payment screenshot, amount, purchase reference and member; approves or rejects with a reason, then activates purchase or enrollment as applicable. |
| FR05 | Each class supports package only, walk-in only or both. For both, the member selects a funding method explicitly. |
| FR06 | Administrator updates or cancels a session. The system records changes, adjusts affected bookings and notifies members and instructor. |
| FR07 | Instructor sets blocked intervals and free time slots. Assignment validation prevents conflicts with blocks and existing classes. |
| FR08 | Instructor sees upcoming assigned classes, time, room, assignment status and roster. |
| FR09 | Instructor accepts or declines manual assignments. Auto accept is enabled by default per instructor; disabling it makes future assignments require acceptance. |
| FR10 | Member sees purchased packages, original credits, remaining usable credits, expiry if applicable and credit transaction history. |
| FR11 | Member sees upcoming and past bookings, session details, booking mode and payment/booking status. |
| FR12 | Member can cancel their confirmed booking only before the 24-hour cutoff. The server evaluates the current session start time. |
| FR13 | Package booking validates sufficient eligible credits; walk-in booking skips credits and follows the payment approval workflow. |

# 4 Required screens

Administrator: class and package management; scheduling calendar;
instructor assignment; payment review queue; enrollment and member
lookup; schedule changes and cancellation; audit and purchase history.

Member: published calendar and class details; package purchase and
payment proof submission; booking method selection; My Credits and
Purchases; My Bookings and cancellation.

Instructor: My Classes; availability calendar with blocked/free
intervals; pending assignments; auto accept setting; session roster.

# 5 Booking business logic

<img src="media/image1.png" style="width:6.7in;height:4.71343in" />

Figure 1 Package and walk-in booking paths. Failed eligibility, time,
duplicate or capacity validation returns a specific reason without a
deduction or confirmed enrollment.

| **Rule** | **Required behavior** |
|----|----|
| Common checks | Only published, future, non-cancelled sessions are bookable. Prevent duplicate active enrollment and reject a full session. |
| Package path | Find an active approved package eligible for this class and session date. Require remaining credits ≥ credit cost. Deduct credits and create confirmed booking in one transaction. |
| Walk-in path | No credit requirement. Create a pending payment request. After verification, recheck capacity and confirm enrollment atomically. |
| Both modes | Display price and credit cost. Never silently change a selected method or convert an insufficient-credit booking into a walk-in purchase. |
| Admin enrollment | Use the same validation and ledger rules. A payment approval alone must not create an invalid or over-capacity enrollment. |

# 6 Payment verification and credits

A screenshot is evidence for administrator review, not automatic
confirmation of received money. The administrator verifies the actual
receipt against the member, amount and reference before approval.

| **Stage** | **Business logic** |
|----|----|
| Submitted | Store member, purchase type, amount, currency, reference, proof image and submitted time. Mark Pending Review. |
| Approved package | Mark payment Approved and package Active; issue 4 or 8 credits, or configured quantity, exactly once. A package purchase does not automatically book a session unless a target session was requested. |
| Approved walk in | Record the approved payment; recheck session and capacity. Confirm enrollment only if valid. Otherwise mark Paid Awaiting Resolution and offer admin reassignment or refund review. |
| Rejected | Record rejection reason and notify member. Grant no credits and create no confirmed booking. Allow a new submission linked to the original purchase. |
| Repeated action | Approval retries and repeated clicks must not issue credits or enroll the member twice. |
| Refund | Payment approval and cash refund are separate states. Record refund amount, reference, reviewer and completion time; never show refunded until completed. |

# Credit accounting

Use an append-only credit ledger: purchase grant, booking deduction,
cancellation restoration and administrator adjustment with reason.
Available balance is calculated per package; deductions retain the
source package so reversals return to the correct balance. Never allow a
negative balance.

Proposed default: one class uses one credit; consume the eligible
package with the earliest expiry first. Show expired credits separately.
Restoring a cancelled booking reverses the original deduction but does
not silently extend package expiry. A studio cancellation affecting
expired credits needs an administrator extension or replacement
entitlement.

# Payment and booking states

| **Entity** | **States** |
|----|----|
| Payment | Pending Review → Approved or Rejected; Approved → Refund Pending → Refunded when applicable. |
| Booking | Pending Payment → Confirmed or Rejected/Expired; Confirmed → Cancelled by Member, Cancelled by Studio, Attended or No Show. |
| Package | Pending Payment → Active → Exhausted or Expired; rejection creates no usable package. |
| Unallocated approved payment | Paid Awaiting Resolution when a session cannot be confirmed; resolved through reassignment or refund. |

# 7 Instructor assignment and calendar logic

<img src="media/image2.png" style="width:6.7in;height:4.71343in" />

Figure 2 Acceptance follows conflict checks. Auto accept never overrides
blocked time or an existing assignment.

Store availability as dated intervals in the studio timezone. Treat
intervals as start-inclusive and end-exclusive; back-to-back sessions
are allowed unless a buffer is configured. An explicit block takes
precedence over a free slot. Reject overlapping room bookings and
instructor assignments, including pending assignments.

Proposed default: free slots indicate preferred availability; absence of
a free slot does not prevent assignment if no block exists. Publishing
requires an accepted instructor assignment. A declined assignment
returns the session to administrator action. Changes to instructor or
session time revalidate availability and trigger acceptance again when
auto accept is off.

When an instructor adds a block overlapping an already accepted class,
prevent the block and show the conflict. The instructor must request
reassignment; an availability edit must not silently remove a published
class.

# 8 Cancellation and schedule changes

<img src="media/image3.png" style="width:6.7in;height:4.71343in" />

Figure 3 Cancellation policy. Credit restoration and walk-in refund
treatment below are proposed defaults.

Apply the rule as now \< session start − 24 hours. At exactly 24 hours
before start, self cancellation is rejected under the strict meaning of
“before.” For a Wednesday 6 PM class, cancellation is permitted before
Tuesday 6 PM in the studio timezone. The business must confirm whether
exactly 24 hours should instead be allowed.

Proposed default: eligible member cancellation releases the seat and
restores the original credits once. Within the cutoff, self cancellation
is blocked and the booking remains active; any administrator exception
needs a reason. Studio cancellation releases every booking and restores
credits regardless of cutoff. Walk-in cancellation creates a refund
review request rather than automatically issuing cash.

A date/time update must notify affected members and the instructor,
preserve history and revalidate conflicts. Never move confirmed members
silently to another session. Proposed default: for a material time
change, offer cancellation without penalty, including within 24 hours.
Existing bookings remain attached to the revised session until cancelled
or otherwise resolved. Capacity cannot be reduced below active
enrollments; changing mode or price must not retrospectively charge
existing bookings.

# 9 Core data and technical requirements

| **Record** | **Minimum fields** |
|----|----|
| User | ID, name, contact, role, active status; instructor auto accept preference. |
| Class definition | ID, name, description, allowed booking modes, credit cost, walk-in price, eligibility rules. |
| Session | ID, class ID, start/end, timezone, room, capacity, instructor, assignment status, publication status, version. |
| Availability | Instructor ID, start/end, blocked or free type; creator and timestamps. |
| Package product and purchase | Product, quantity, price, eligible classes, expiry rule; member purchase, payment status, activation/expiry dates. |
| Payment | Member, purchase/booking reference, proof file, amount/currency, status, reviewer, review time, rejection/refund details. |
| Booking | Member, session, mode, status, source package/payment, credit cost snapshot, creation/cancellation times and reason. |
| Credit ledger and audit | Transaction ID, package, credit delta, booking/payment reference, reason, actor and timestamp; old/new values for edits. |

Relationships: a class has many sessions; a session has one assigned
instructor and many bookings; a member has many purchases and bookings;
a package purchase has many ledger entries; a payment references its
purchase or walk-in booking. Payment proof files require authenticated,
restricted access.

# Reliability and security

Validate all business rules on the server. Reserve capacity and deduct
credits within database transactions to prevent concurrent overbooking
or overspending. Repeated requests use a unique operation reference.
Store timestamps consistently and display them in the configured studio
timezone, proposed Asia/Yangon. Payment approval permissions, file
type/size checks, audit history and backup recovery are required.

Notify members of payment decisions, confirmed bookings, cancellations
and schedule changes. Notify instructors of assignments and changes.
Notification failures must not undo a completed financial transaction;
retry delivery and retain a delivery log.

# 10 Decisions required before implementation

| **Policy** | **Proposed default or decision needed** |
|----|----|
| Walk-in payment timing | Approval before confirmed enrollment. Pay-at-studio booking requires a separate explicit policy. |
| Pending seat reservation | No seat hold while proof is reviewed. If a hold is wanted, specify expiry, release rules and the approval race behavior. |
| Credits and expiry | One credit per class; define package eligibility, activation date and validity. Do not invent an expiry duration. |
| Cancellation boundary | Strictly more than 24 hours; confirm whether exactly 24 hours is eligible. |
| Refunds and changes | Approve cash refund rules and processing responsibility; approve penalty-free cancellation after material schedule changes. |
| Availability and publication | Free slots advisory; blocks mandatory; instructor accepted before publication. Confirm these defaults. |
| Additional policies | Define no-show treatment, instructor response deadline, booking cutoff and any room turnaround buffer. Waitlist is optional and outside this draft. |

# 11 Acceptance criteria

| **Test** | **Expected result** |
|----|----|
| AC01 Role isolation | Member cannot create sessions or approve payments; instructor cannot access another instructor’s private availability or member payment proofs. |
| AC02 Booking modes | Package-only blocks walk-in; walk-in-only skips credits; Both displays both choices. |
| AC03 Package purchase | Approved 4-class purchase issues exactly 4 credits. A second approval attempt issues zero additional credits. |
| AC04 Insufficient credit | Balance 0 or below required cost blocks package booking with no booking or ledger change. |
| AC05 Valid credit booking | Balance 4 with cost 1 confirms one booking and leaves 3 credits. Retry does not deduct again. |
| AC06 Walk-in booking | Member with zero credits can submit walk-in payment proof. Approval confirms only when capacity remains. |
| AC07 Full session after payment | If another member takes the last seat before approval, approved payment enters resolution; capacity is not exceeded. |
| AC08 Concurrent requests | Two requests for the last seat produce at most one confirmation. Two requests using one credit never create a negative balance. |
| AC09 Cancellation times | 25 hours before start allows cancellation; 23 hours and exactly 24 hours reject it under the proposed strict cutoff. |
| AC10 Credit reversal | Eligible cancellation restores the original credit cost once. Repeated cancellation does not add credits again. |
| AC11 Studio cancellation | All active bookings cancel, credits restore regardless of cutoff, cash payments enter refund review and notifications are queued. |
| AC12 Instructor acceptance | New instructor defaults to auto accept. Turning it off makes new assignments Pending; accept and decline are recorded. |
| AC13 Calendar conflicts | Blocked or overlapping assignment is rejected even with auto accept on. Back-to-back intervals are permitted when buffer is zero. |
| AC14 Session changes | Time or instructor change revalidates availability; affected users receive notice. Capacity below enrolled count is rejected. |
| AC15 Package eligibility | Expired or class-ineligible package cannot fund booking even if displayed balance is positive. |
| AC16 Payment rejection | Rejected proof grants no credit or confirmation; member sees the reason and can resubmit. |
| AC17 Member dashboard | Purchases, balances and bookings match their ledger and session records; cancelled items retain history. |
| AC18 Timezone and audit | Cutoff uses studio timezone consistently across devices. Approval, overrides and schedule edits identify actor and time. |

Business signoff: confirm the decisions in Section 10, then baseline
this document for development and user acceptance testing. This
specification defines desired behavior; it does not claim that an
existing application already implements it.
