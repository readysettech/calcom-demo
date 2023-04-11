# ReadySet cal.com demo

This repository contains instructions and scripts for trying out ReadySet with
[cal.com][], to demonstrate how easy it is to get up and running and speeding up
queries using ReadySet with a real-world, production-scale web application.

[cal.com]: https://github.com/calcom/cal.com

## Prerequisites

In order to run cal.com, you'll need the following installed on your machine:

- [Node.js](https://nodejs.org/en) (>=15.x <17)
- [yarn](https://yarnpkg.com/)
- A PostgreSQL server

In addition, in order to run ReadySet for this demo, you'll need a local release
build of the ReadySet binary. See [the readyset
documentation](https://github.com/readysettech/readyset#development) for more
information on prerequisites for building ReadySet.

## Step 1: Create and seed the database

First, create a database in your PostgreSQL server for cal.com to use to store
its data:

```shellsession
$ psql
localhost/postgres=# create database calcom;
CREATE DATABASE
```

This repository includes a sql DB dump file containing a large amount of data,
which we'll use later to benchmark a query to compare ReadySet against
PostgreSQL. To load this data, along with all the DDL necessary to run cal.com,
into the postgres database, run the following command:

``` shellsession
cat calcom.sql.gz.1 calcom.sql.gz.2 calcom.sql.gz.3 | gunzip -c | psql calcom
```

## Step 2: Run cal.com

First, clone cal.com:

```shellsession
$ git clone git@github.com:calcom/cal.com
```

And install dependencies:

``` shellsession
$ cd cal.com
$ yarn install
```

To configure cal.com to point at your local database, first copy the
`.env.example` file to `.env`:

``` shellsession
$ cp .env.example .env
```

Then edit the file such that `DATABASE_URL` contains the connection information
for your PostgreSQL database.

Now, to run the `cal.com` dev server, run:

``` shellsession
$ yarn dev
```

Once a bit of time has passed, you should be able to access `cal.com` at
http://localhost:3000

## Step 3: Run ReadySet

To run ReadySet connected to your postgresql database, run the following
command:

``` shellsession
$ path/to/readyset \
    --standalone \
    --deployment calcom \
    --database-type postgresql \
    --upstream-db-url postgresql://<user>:<password>@127.1/calcom \
    -a 0.0.0.0:5435
```

Once ReadySet outputs a log line containing `Streaming replication started`,
it's ready to use for the application

## Step 5: Connect cal.com to ReadySet

To point cal.com at ReadySet, edit the `.env` file to add port `5435` to
the configured `DATABASE_URL`. Then, restart the dev server. cal.com is now
using ReadySet!

## Step 4: Cache a query

The query from cal.com that we'll be caching is:

``` sql
SELECT
    min("public"."Booking"."startTime"),
    count("public"."Booking"."recurringEventId"),
    "public"."Booking"."recurringEventId" FROM "public"."Booking"
WHERE "public"."Booking"."recurringEventId" IS NOT NULL
AND "public"."Booking"."userId" = $1
GROUP BY "public"."Booking"."recurringEventId"
```

To tell ReadySet to cache this query, first open a psql shell connected to port
5435:

``` shellsession
$ psql -p 5435
```

Then issue the `CREATE CACHE FROM` command with the query:

``` shellsession
localhost/calcom=> CREATE CACHE FROM SELECT
    min("public"."Booking"."startTime"),
    count("public"."Booking"."recurringEventId"),
    "public"."Booking"."recurringEventId" FROM "public"."Booking"
WHERE "public"."Booking"."recurringEventId" IS NOT NULL
AND "public"."Booking"."userId" = $1
GROUP BY "public"."Booking"."recurringEventId";
```

## Step 5: Benchmarking the query

Let's run a more thorough benchmark to compare the latency and throughput of
executing that query against Postgres vs ReadySet. To do this, we'll use
[pgbench](https://www.postgresql.org/docs/current/pgbench.html), which is a
Postgres benchmarking tool distributed with Postgres itself.

This repository contains a file `benchmark.sql`, which can be used as a
`pgbench` custom benchmark script. We can use this file to run a `pgbench`
benchmark for the query we just created a cache for. First, let's run against
postgres itself, to establish a baseline:

``` shellsession
$ pgbench -Mprepared -j32 -s32 -c32 -f ./benchmark.sql -T30
```

Now, let's run against ReadySet to compare:

``` shellsession
$ pgbench -Mprepared -j32 -s32 -c32 -f ./benchmark.sql -T30 -p5435
```
