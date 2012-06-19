# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST;
use strict;

use constant NAME => 'REST';

use constant REQUIRED_MODULES => [
    {
      package => 'JSON',
      module  => 'JSON',
      version => 0,
    },
    {
      package => 'YAML-Syck', 
      module  => 'YAML::Syck',
      version => 0,
    },
    {
      package => 'XML-Simple',
      module  => 'XML::Simple',
      version => 0,
    },
];

__PACKAGE__->NAME;
