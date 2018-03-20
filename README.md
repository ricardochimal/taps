# Taps (2) -- simple database import/export app

A simple database agnostic import/export app to transfer data to/from a remote database.

*Forked and updated* with fixes and improvements. Integrates fixes and updates from [taps-taps](https://github.com/wijet/taps) and [tapsicle](https://github.com/jiffyondemand/tapsicle) forks.

## Installation

Renamed gem

    $ gem install taps2

By default, Taps will attempt to create a SQLite3 database for sessions. Unless you specify a different database type, you'll need to install SQLite3. (See _Environment Variables_ for alternative session databases.)

    $ gem install sqlite3

Install the gems to support databases you want to work with, such as MySQL or PostgreSQL.

    $ gem install mysql2
    $ gem install pg

## Configuration: Environment Variables

_All environment variables are optional._

The `TAPS_DATABASE_URL` variable specifies the database URI where session data is stored on CLI or Server.
The `DATABASE_URL` variable is a fallback (and compatible with Heroku) if `TAPS_DATABASE_URL` is not specified.
By default, Taps will create a SQLite3 database.

The `TAPS_LOGIN` and `TAPS_PASSWORD` variables are used for default Basic Authentication.

The `TAPS_YAML_ENGINE` variable lets you specify a YAML engine such as "psych".

The `NO_DEFAULT_DATABASE_URL` variable allows you to require a database URI be sent in the `body` of the request that initiates a Taps session. (Default behavior will use the database URI specified when starting the server.)

The `NO_DUMP_MARSHAL_ERRORS` variable allows you to disable dumping of marshalled data that caused an error.

The `NO_DEFLATE` variable allows you to disable gzip compression (`Rack::Deflater`) on the server.

## Usage: Server

Here's how you start a taps server

    $ taps2 server postgres://localdbuser:localdbpass@localhost/dbname httpuser httppassword

You can also specify an encoding in the database url

    $ taps2 server mysql://localdbuser:localdbpass@localhost/dbname?encoding=latin1 httpuser httppassword

## Usage: Client

When you want to pull down a database from a taps server

    $ taps2 pull postgres://dbuser:dbpassword@localhost/dbname http://httpuser:httppassword@example.com:5000

or when you want to push a local database to a taps server

    $ taps2 push postgres://dbuser:dbpassword@localhost/dbname http://httpuser:httppassword@example.com:5000

or when you want to transfer a list of tables

    $ taps2 push postgres://dbuser:dbpassword@localhost/dbname http://httpuser:httppassword@example.com:5000 --tables logs,tags

or when you want to transfer tables that start with a word

    $ taps2 push postgres://dbuser:dbpassword@localhost/dbname http://httpuser:httppassword@example.com:5000 --filter '^log_'

## Troubleshooting

* "Error: invalid byte sequence for encoding" can be resolved by adding `encoding` to database URI (https://github.com/ricardochimal/taps/issues/110)
  * *Example:* `taps2 server mysql://root@localhost/example_database?encoding=UTF8 httpuser httppassword`
* SQLite3 database URI may require three slashes (e.g. `sqlite3:///path/to/file.db`)
  * Make sure to use an absolute/full path to the file on the server

## Known Issues

* Foreign key constraints get lost in the schema transfer
* Indexes may drop the "order" (https://github.com/ricardochimal/taps/issues/111)
* String fields with only numbers may get parsed as a number and lose leading zeros or add decimals (https://github.com/ricardochimal/taps/issues/106)
* Tables without primary keys will be incredibly slow to transfer. This is due to it being inefficient having large offset values in queries.
* Multiple schemas are currently not supported (https://github.com/ricardochimal/taps/issues/97)
* Taps does not drop tables when overwriting database (https://github.com/ricardochimal/taps/issues/94)
* Oracle database classes not fully supported (https://github.com/ricardochimal/taps/issues/89)
* Some blank default values may be converted to NULL in MySQL table schemas (https://github.com/ricardochimal/taps/issues/88)
* Conversion of column data types can cause side effects when going from one database type to another
  * MySQL `bigint` converts to PostgreSQL `string` (https://github.com/ricardochimal/taps/issues/77)
* Passwords in database URI can cause issues with special characters (https://github.com/ricardochimal/taps/issues/74)

## Feature Requests

* Allow a single Taps server to serve data from different databases (https://github.com/ricardochimal/taps/issues/103)

## Meta

Maintained by [Joel Van Horn](http://github.com/joelvh)

Written by Ricardo Chimal, Jr. (ricardo at heroku dot com) and Adam Wiggins (adam at heroku dot com)

Early research and inspiration by Blake Mizerany

Released under the MIT License: http://www.opensource.org/licenses/mit-license.php

http://github.com/ricardochimal/taps

Special Thanks to Sequel for making this tool possible http://sequel.rubyforge.org/
