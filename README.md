[![Gem Version](https://badge.fury.io/rb/grack.svg)](http://badge.fury.io/rb/grack)
[![Build Status](https://travis-ci.org/grackorg/grack.svg?branch=master)](https://travis-ci.org/grackorg/grack)
[![Coverage Status](https://coveralls.io/repos/grackorg/grack/badge.svg?branch=master&service=github)](https://coveralls.io/github/grackorg/grack?branch=master)
[![Dependency Status](https://gemnasium.com/grackorg/grack.svg)](https://gemnasium.com/grackorg/grack)

# Grack - Ruby/Rack Git Smart HTTP Server Handler

This project aims to replace the builtin git-http-backend CGI handler
distributed with C Git with a Rack application.

## Links

* Homepage :: https://github.com/grackorg/grack
* Source :: https://github.com/grackorg/grack.git

## Description

This project aims to replace the builtin git-http-backend CGI handler
distributed with C Git with a Rack application. By default, Grack uses calls to
git on the system to implement Smart HTTP. Since the git-http-backend is really
just a simple wrapper for the upload-pack and receive-pack processes with the
'--stateless-rpc' option, this does not actually re-implement very much.
However, it is possible to use a different backend by specifying a different
Adapter.

The default git-http-backend only runs as a CGI script, and specifically is
only targeted for Apache 2.x usage (it requires PATH_INFO to be set and
specifically formatted).  So, instead of trying to get it to work with other
CGI capable webservers (Lighttpd, etc), we can get it running on nearly every
major and minor webserver out there by making it Rack capable.  Rack
applications can run with the following handlers:

* CGI
* FCGI
* Mongrel (and EventedMongrel and SwiftipliedMongrel)
* WEBrick
* SCGI
* LiteSpeed
* Thin

These web servers include Rack handlers in their distributions:

* Ebb
* Fuzed
* Phusion Passenger (which is mod_rack for Apache and for nginx)
* Unicorn

With [Warbler](http://caldersphere.rubyforge.org/warbler/classes/Warbler.html),
and JRuby, we can also generate a WAR file that can be deployed in any Java web
application server (Tomcat, Glassfish, Websphere, JBoss, etc).

By default, Grack uses calls to git on the system to implement Smart HTTP.
Since the git-http-backend is really just a simple wrapper for the upload-pack
and receive-pack processes with the '--stateless-rpc' option, this does not
actually re-implement very much. However, it is possible to use a different
backend by specifying a different Adapter. See below for a list.

Note that while it is technically possible to host non-bare repositories with
this gem, it is discouraged.  The only somewhat safe option is to serve such a
repository as read-only since there is a greater risk of arbitrary filesystem
traversal when a checkout tree must be traversed to reach the repository
administrative area (`.git` directory).  Additionally, any recent version of Git
prevents pushes into non-bare repositories by default since pushing into the
currently checked out branch can effectively "break" the checkout tree.

## Synopsis

In `config.ru`:

```ruby
require 'grack/app'
require 'grack/git_adapter'

config = {
  :root => '/path/to/bare/repositories',
  :allow_push => true,
  :allow_pull => true,
  :git_adapter_factory => ->{ Grack::GitAdapter.new }
}

run Grack::App.new(config)
```

Then run:

```sh
$ bundle exec rackup --host 127.0.0.1 --port 8080 config.ru
$ git clone http://localhost:8080/your-repository.git
```

### Git Adapters

Grack makes calls to the git binary through the GitAdapter abstraction class.
Grack can be made to use a different backend by specifying a call-able object,
such as a lambda, in Grack's configuration that provides new adapter instances
per request. For example:

```ruby
Grack::App.new(:git_adapter_factory => ->{ MyAdapter.new })
```

Alternative adapters available:
* [rjgit_grack](http://github.com/grackorg/rjgit_grack) lets Grack use the
  [RJGit](http://github.com/repotag/rjgit) gem to implement Smart HTTP in pure
  JRuby.

### Developing Adapters

Adapters are abstraction classes that handle the actual implementation of the
Smart HTTP protocol (advertising refs, uploading and receiving packfiles). Such
abstraction classes must have the following methods:

```ruby
MyAdapter.repository_path=(repository_path)
MyAdapter.exist?
MyAdapter.handle_pack(kind, io_in, io_out, opts = {})
MyAdapter.file(path)
MyAdapter.update_server_info
MyAdapter.allow_push?
MyAdapter.allow_pull?
```

See `Grack::GitAdapter` for more detailed documentation and an example
implementation.

## Features

* Supports Git Smart HTTP protocol.
* Supports Git Basic HTTP protocol.
* Limits push/pull access globally and per-repository.
* Thread safe operation.

### Hooks

By default, grack doesn't support git hooks. This is because the default GitAdapter directly streams the requests to the `git-receive-pack` and `git-upload-pack` processes. However, alternative adapters may implement hooks.

Adapters that support hooks:

* [rjgit_grack](http://github.com/grackorg/rjgit_grack)

## Known Bugs/Limitations

* Will likely block fully evented web servers when using the stock Git adapter.

## Runtime Requirements

* Ruby >=1.9.3
* Git >=1.7 (if using the included Git adapter)
* rack (>= 0)

## Development Requirements

* All runtime requirements
* rake (>= 10.1.1, ~> 10.1)
* rack-test (>= 0.6.3, ~> 0.6)
* minitest (>= 5.8.0, ~> 5.8)
* mocha (>= 1.1.0, ~> 1.1)
* simplecov (>= 0.10.0, ~> 0.10)
* yard (>= 0.8.7.3, ~> 0.8.7)
* redcarpet (>= 3.1.0, ~> 3.1)
* github-markup (>= 1.0.2, ~> 1.0)
* pry (~> 0)

## Contributing

Contributions for bug fixes, documentation, extensions, tests, etc. are
encouraged.

1. Clone the repository.
2. Fix a bug or add a feature.
3. Add tests for the fix or feature.
4. Make a pull request.

## Development

After checking out the source, run:

```sh
$ bundle install
$ bundle exec rake test yard
```

This will install all dependencies, run the tests/specs, and generate the
documentation.

## Authors

Thanks to all contributors.  Without your help this project would not exist.

* Scott Chacon :: schacon@gmail.com
* Dawa Ometto :: d.ometto@gmail.com
* Jeremy Bopp :: jeremy@bopp.net

## License

```
(The MIT License)

Copyright (c) 2015 Scott Chacon <schacon@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
