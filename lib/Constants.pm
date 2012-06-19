# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::Constants;
use strict;
use base qw(Exporter);
our @EXPORT = qw(
    STATUS_OK
    STATUS_CREATED
    STATUS_ACCEPTED
    STATUS_NO_CONTENT
    STATUS_MULTIPLE_CHOICES
    STATUS_BAD_REQUEST
    STATUS_NOT_FOUND
    STATUS_GONE
    ACCEPT_CONTENT_TYPES
);

use constant STATUS_OK               => 200;
use constant STATUS_CREATED          => 201;
use constant STATUS_ACCEPTED         => 202;
use constant STATUS_NO_CONTENT       => 204;
use constant STATUS_MULTIPLE_CHOICES => 300;
use constant STATUS_BAD_REQUEST      => 400;
use constant STATUS_NOT_FOUND        => 404;
use constant STATUS_GONE             => 410;

use constant ACCEPT_CONTENT_TYPES => (
    'text/html', 
    'application/json', 
    'text/xml', 
);

1;
