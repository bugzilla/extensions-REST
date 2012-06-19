# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::View::XML;

use strict;

use base qw(Bugzilla::Extension::REST::View);

use Bugzilla::Extension::REST::Util qw(stringify_json_objects);

use XML::Simple;

sub view {
    my ($self, $data) = @_;
    stringify_json_objects($data);
    my $xs = XML::Simple->new(
        XMLDecl       => 1, 
        AttrIndent    => 1, 
        ForceArray    => 1,
        NoAttr        => 1, 
        RootName      => 'result', 
        SuppressEmpty => 1, 
    );
    return $xs->XMLout($data);
}

1;
