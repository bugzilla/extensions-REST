# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::View::JSON;

use strict;

use base qw(Bugzilla::Extension::REST::View);

use Bugzilla;

use JSON;

sub view {
    my ($self, $data) = @_;
    my $json = JSON->new->utf8;
    $json->allow_blessed(1);
    $json->convert_blessed(1);
    # This may seem a little backwards,  but what this really means is
    # "don't convert our utf8 into byte strings,  just leave it as a
    # utf8 string."
    $json->utf8(0) if Bugzilla->params->{'utf8'};
    return $json->allow_nonref->encode($data); 
}

1;
