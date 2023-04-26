# ReadySet Cal.com demo

This repository contains instructions and scripts for trying out ReadySet with
[Cal.com][]. The goal is to demonstrate how easy it is to get up and running
using ReadySet with a real-world, production-scale web application, and to show
an example of the kind of improvements you might see in throughput and latency.

[Cal.com]: https://github.com/calcom/cal.com

## Prerequisites

In order to run Cal.com, you'll need the following installed on your machine:

- [Node.js](https://nodejs.org/en) (version 15 or 16)
- [yarn](https://yarnpkg.com/)
- A PostgreSQL server (version 13 or 14)

In addition, in order to run ReadySet for this demo, you'll need a local
release build of the ReadySet binary. See [the readyset
documentation](https://github.com/readysettech/readyset#development) for more
information on prerequisites for building ReadySet.

Note that you must follow the above instructions to generate a **release**
build; if you are using a development build, you may see significantly lower
performance numbers than expected. The above instructions do include the
`--release` flag, but this point is worth emphasizing here since some users
who are already familiar with ReadySet may be used to creating debug builds,
and might therefore gloss over the above instructions.

## Step 1: Set up PostgreSQL and seed the database

The following steps expect the `postgres` user to exist, so make sure to create
this user and either set it as the default (via e.g. `.pgpass`), or specify it
manually in the `psql` flags of the commands that follow. You should also make
sure to create the `postgres` user with the necessary permissions to create a
new database.

If you don't have Postgres or PgBench installed, install them:

```shellsession
sudo yum install -y postgresql15 postgresql15-contrib
```

First, create a database in your PostgreSQL server for Cal.com to use to store
its data:

```shellsession
$ psql
localhost/postgres=# create database calcom;
CREATE DATABASE
```

This repository includes a SQL DB dump file containing a large amount of data,
which we'll use later to benchmark a query to compare ReadySet against
PostgreSQL.

To load this data - along with all the DDL necessary to run Cal.com - into the
Postgres database, run the following command:

``` shellsession
cat calcom.sql.gz.1 calcom.sql.gz.2 calcom.sql.gz.3 | gunzip -c | psql calcom
```

Finally, note that the `wal_level` setting must be set to `logical`. You can
check the value of this setting in a `psql` shell by running `SHOW wal_level;`.
If it is not set to `logical`, update the setting in your `postgresql.conf`
file and restart Postgres.

## Step 2: Run Cal.com

First, clone the Cal.com repository:

```shellsession
$ git clone git@github.com:calcom/cal.com
```

Next, install dependencies:

``` shellsession
$ cd cal.com
$ yarn install
```

To configure Cal.com to point at your local database, first copy the
`.env.example` file to `.env`:

``` shellsession
$ cp .env.example .env
```

After that, use the `openssl rand -base64 32` command to generate a key and add
it under `NEXTAUTH_SECRET` in the `.env` config file. Similarly, use the
command `openssl rand -base64 24` to generate a key and add it to the
`CALENDSO_ENCRYPTION_KEY` field.

Then edit the file such that `DATABASE_URL` contains the connection information
for your PostgreSQL database. Note that this necessarily includes editing the
default database string of `calendso` and replacing it with `calcom`. It also
likely includes changing the port in the connection string, as PostgreSQL
typically defaults to listening on port 5432, whereas the example Cal.com
config file uses port 5450.

If you're deploying to the internet, you'll also need to set NEXTAUTH_URL to be the external ip and port.

Now, to start the Cal.com dev server, run:

``` shellsession
$ yarn dev
```

Once a bit of time has passed, you should be able to access Cal.com at
http://localhost:3000

From there, you can log in using the username `griffin@readyset.io` and a
password of `password`.

## Step 3: Run ReadySet

To start ReadySet and have it connect to your PostgreSQL database, run the
following command:

``` shellsession
$ path/to/readyset \
    --standalone \
    --deployment calcom \
    --database-type postgresql \
    --upstream-db-url postgresql://<user>:<password>@127.1/calcom \
    -a 0.0.0.0:5435
```

Once ReadySet outputs a log line containing `Streaming replication started`,
it's ready to use for the application. Note that it may take some time to reach
this point.

## Step 4: Connect Cal.com to ReadySet

To point Cal.com at ReadySet, edit the `.env` file to add port `5435` to
the configured `DATABASE_URL`. Then, restart the dev server. Cal.com is now
using ReadySet!

## Step 5: Cache a query

The query from Cal.com that we'll be caching is:

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

## Step 6: Benchmarking the query

Let's run a more thorough benchmark to compare the latency and throughput of
executing that query against Postgres vs ReadySet. To do this, we'll use
[pgbench](https://www.postgresql.org/docs/current/pgbench.html), which is a
Postgres benchmarking tool distributed with Postgres itself.

This repository contains a file `benchmark.sql`, which can be used as a
`pgbench` custom benchmark script. We can use this file to run a `pgbench`
benchmark for the query we just created a cache for. First, let's run against
Postgres itself, to establish a baseline:

``` shellsession
$ pgbench -Mprepared -j32 -s32 -c32 -f ./benchmark.sql -T30 -U postgres calcom
```

Now, let's run against ReadySet to compare:

``` shellsession
$ pgbench -Mprepared -j32 -s32 -c32 -f ./benchmark.sql -T30 -U postgres -h 127.1 -p5435 calcom
```
