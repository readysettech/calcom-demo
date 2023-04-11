SELECT
    min("public"."Booking"."startTime"),
    count("public"."Booking"."recurringEventId"),
    "public"."Booking"."recurringEventId" FROM "public"."Booking"
WHERE "public"."Booking"."recurringEventId" IS NOT NULL
AND "public"."Booking"."userId" = 14
GROUP BY "public"."Booking"."recurringEventId"
