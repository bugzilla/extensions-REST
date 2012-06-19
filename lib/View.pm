# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::View;

use strict;

use Bugzilla::Error;

use constant CONTENT_TYPE_VIEW_MAP => {
    'text/html'        => 'HTML', 
    'application/json' => 'JSON', 
    'text/xml'         => 'XML', 
};

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    
    my $self = {};
    $self->{_content_type} = shift || 'application/json'; 
    
    my $view = CONTENT_TYPE_VIEW_MAP->{$self->{_content_type}};
    $view || ThrowUserError('rest_illegal_content_type_view',
                            { content_type => $self->{_content_type} });
    
    my $module = "Bugzilla::Extension::REST::View::$view";
    eval "require $module";
    if ($@) {
        die "Could not load view $module: $!"; 
    }
    bless $self, $module;
     
    return $self;
}

sub view {
    my ($self, $data) = @_;
    # Implemented by individual view modules
}

1;
