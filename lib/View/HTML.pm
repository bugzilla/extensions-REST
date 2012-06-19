# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::View::HTML;

use strict;

use base qw(Bugzilla::Extension::REST::View);

use Bugzilla::Extension::REST::Util qw(stringify_json_objects);

use YAML::Syck;

sub view {
    my ($self, $data) = @_;
    stringify_json_objects($data);
    my $content = "<html><title>Bugzilla::REST::API</title><body>" .
                  "<pre>" . Dump($data) . "</pre></body></html>";
    return $content;
}

1;
