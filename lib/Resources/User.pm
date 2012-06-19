# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::Resources::User;

use strict;

use base qw(Exporter Bugzilla::WebService Bugzilla::WebService::User);

use Bugzilla::Extension::REST::Util;
use Bugzilla::Extension::REST::Constants;

use Tie::IxHash;
use Data::Dumper;

#############
# Resources #
#############

# IxHash keeps them in insertion order, and so we get regexp priorities right.
our $_resources = {};
tie(%$_resources, "Tie::IxHash",
    qr{/user$} => {
        GET => 'user_GET'
    }, 
    qr{/user/([^/]+)$} => {
        GET => 'one_user_GET'
    }
);

sub resources { return $_resources };

###########
# Methods #
###########

sub user_GET {
    my ($self, $params) = @_;

    my $include_disabled = exists $params->{include_disabled} 
                           ? $params->{include_disabled} 
                           : 0;
    my $match_value = ref $params->{match} 
                      ? $params->{match}
                      : [ $params->{match} ];

    my $result = $self->get({ match => $match_value, 
                              include_disabled => $include_disabled });

    my @adjusted_users = map { $self->_fix_user($params, $_) }
                         @{ $result->{users} };
    
    $self->bz_response_code(STATUS_OK);
    return { users => \@adjusted_users };
}

sub one_user_GET {
    my ($self, $params) = @_;

    my $nameid = $self->bz_regex_matches->[0];
    
    my $param = "names";
    if ($nameid =~ /^\d+$/) {
        $param = "ids";
    }
    
    my $result = $self->get({ $param => $nameid });

    my $adjusted_user = $self->_fix_user($params, $result->{users}[0]);

    $self->bz_response_code(STATUS_OK);
    return $adjusted_user;
}

##################
# Helper Methods #
##################

sub _fix_user {
    my ($self, $params, $user) = @_;

    $user->{ref} = ref_urlbase() . "/user/" . $user->{id};

    return $user;
}

1;
