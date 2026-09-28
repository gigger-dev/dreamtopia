# REST API

Base URL: `/api`. Authentication: `Authorization: Bearer <accessToken>`.
Dates are ISO 8601 UTC timestamps. Fees and discounts are integer currency units (MMK by default).

| Method / path | Access | Purpose |
|---|---|---|
| POST `/auth/register` | Public, rate limited | `{name,email,password}`; always creates a member |
| POST `/auth/login` | Public, rate limited | `{email,password}` → token and account |
| GET `/me` | Signed in | Account, credits, instructor settings, total classes taught |
| GET `/settings` | Signed in | Studio timezone, currency, bank instructions |
| GET `/sessions?from=...&to=...` | Signed in | Calendar; members only see published classes, instructors only their own |
| POST `/sessions` | Admin | Create session; requires instructor for pole classes/trials |
| POST `/sessions/:id/cancel` | Admin | Cancel session and restore reserved credits |
| DELETE `/sessions/:id` | Admin | Soft-delete and cancel; retain history |
| POST `/sessions/:id/accept` | Assigned instructor | Accept an admin-approved assignment |
| POST `/sessions/:id/complete` | Admin / assigned instructor | Count a session as taught after its end |
| GET `/sessions/:id/quote?code=...` | Signed in | Server-calculated price and discount |
| POST `/proofs` | Member | Multipart field `file`; PNG/JPEG/WebP ≤5 MB |
| GET `/proofs/:id` | Admin / proof owner | Private image bytes |
| POST `/bookings` | Member | `{sessionId,paymentMethod,proofId?,promoCode?}` |
| GET `/bookings` | Signed in | Role-scoped bookings and attendance |
| POST `/bookings/:id/cancel` | Booking owner | More than 24 hours before session |
| POST `/bookings/:id/approve` | Admin | Confirm payment and booking |
| POST `/bookings/:id/reject` | Admin | `{reason}`; restore reserved credit |
| PATCH `/bookings/:id/attendance` | Admin / assigned instructor | `{attendance: PRESENT\|ABSENT\|UNMARKED}` |
| GET / POST `/instructors` | Admin | Instructor profiles and teaching totals / create profile |
| POST `/instructors/:id/link` | Admin | Link matching registered email after manual identity verification |
| PATCH `/instructor/settings` | Instructor | `{autoAccept: boolean}` |
| GET / POST `/instructor/blocks` | Instructor | List / add `{startsAt,endsAt,reason}` |
| DELETE `/instructor/blocks/:id` | Block owner | Remove unavailability |
| GET `/members` | Admin | Members, credit balances, attendance counts |
| POST `/members/:id/credits` | Admin | Add package `{amount,reason}` |
| GET `/credits` | Member | Own credit ledger |
| GET / POST `/promotions` | Admin | List / create `{code,percent,expiresAt}` |
| PATCH `/promotions/:id` | Admin | `{active: boolean}` |
| POST `/campaigns` | Admin | `{title,body}` → member in-app notifications |
| GET `/notifications` | Signed in | Own inbox |
| PATCH `/notifications/:id/read` | Notification owner | Mark read |
| GET `/requests` | Admin / member | All / own preferred timeslots |
| POST `/requests` | Member | `{type,startsAt,endsAt,note}` |
| PATCH `/requests/:id` | Admin | `{status: REVIEWED\|DECLINED,response}` |

## Example create session

```json
{
  "title": "Pole Foundations",
  "type": "POLE_CLASS",
  "startsAt": "2026-10-01T11:30:00.000Z",
  "endsAt": "2026-10-01T12:30:00.000Z",
  "capacity": 6,
  "price": 35000,
  "level": "Beginner",
  "description": "Build confidence with foundational spins and transitions.",
  "instructorId": "<UUID from instructor profile>"
}
```

Session types: `POLE_CLASS`, `TRIAL`, `PRACTICE`, `RENTAL`.
Payment methods: `BANK_TRANSFER`, `CREDITS`.

Errors use an HTTP status and `{message: string | string[]}`. Request DTOs reject undeclared fields. No client-provided price, member ID, balance, or role is accepted when booking or registering.
