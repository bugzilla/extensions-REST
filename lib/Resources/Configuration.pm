# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::Resources::Configuration;

use strict;

use base qw(Exporter Bugzilla::WebService);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Keyword;
use Bugzilla::Product;
use Bugzilla::Status;
use Bugzilla::Field;
use Bugzilla::WebService::Bugzilla;

use Bugzilla::Extension::REST::Util;
use Bugzilla::Extension::REST::Constants;

use Digest::MD5 qw(md5_base64);
use Tie::IxHash;
use Data::Dumper;

#############
# Resources #
#############

# IxHash keeps them in insertion order, and so we get regexp priorities right.
our $_resources = {};
tie(%$_resources, "Tie::IxHash",
    qr{/configuration} => { 
        GET => 'configuration_GET'
    },
);

sub resources { return $_resources };

###########
# Methods #
###########

sub configuration_GET {
    my ($self, $params) = @_;
    my $user = Bugzilla->user;

    # If the 'requirelogin' parameter is on and the user is not
    # authenticated, return empty fields.
    if (Bugzilla->params->{'requirelogin'} && !$user->id) {
	    $self->_bz_response_code(STATUS_OK);
	    return $self->_result_from_template();
    }

    # Get data from the shadow DB as they don't change very often.
    Bugzilla->switch_to_shadow_db;

    # Pass a bunch of Bugzilla configuration to the template
    my $vars = {};
    $vars->{'priority'}  = get_legal_field_values('priority');
    $vars->{'severity'}  = get_legal_field_values('bug_severity');
    $vars->{'platform'}  = get_legal_field_values('rep_platform');
    $vars->{'op_sys'}    = get_legal_field_values('op_sys');
    $vars->{'keyword'}    = [map($_->name, Bugzilla::Keyword->get_all)];
    $vars->{'resolution'} = get_legal_field_values('resolution');
    $vars->{'status'}    = get_legal_field_values('bug_status');
    $vars->{'custom_fields'} =
        [ grep {$_->is_select} Bugzilla->active_custom_fields ];

    # Include a list of product objects.
    if ($params->{'product'}) {
        my @products = $params->{'product'};
        foreach my $product_name (@products) {
            # We don't use check() because config.cgi outputs mostly
            # in XML and JS and we don't want to display an HTML error
            # instead of that.
            my $product = new Bugzilla::Product({ name => $product_name });
            if ($product && $user->can_see_product($product->name)) {
                push (@{$vars->{'products'}}, $product);
            }
        }
    } else {
        $vars->{'products'} = $user->get_selectable_products;
    }

    # We set the 2nd argument to 1 to also preload flag types.
    Bugzilla::Product::preload($vars->{'products'}, 1);

    print STDERR Dumper $params;

    # Allow consumers to specify whether or not they want flag data.
    if (defined $params->{'flags'}) {
        $vars->{'show_flags'} = $params->{'flags'};
    }
    else {
        # We default to sending flag data.
        $vars->{'show_flags'} = 1;
    }

    # Create separate lists of open versus resolved statuses.  This should really
    # be made part of the configuration.
    my @open_status;
    my @closed_status;
    foreach my $status (@{$vars->{'status'}}) {
        is_open_state($status) ? push(@open_status, $status) 
                               : push(@closed_status, $status);
    }
    $vars->{'open_status'} = \@open_status;
    $vars->{'closed_status'} = \@closed_status;

    # Generate a list of fields that can be queried.
    my @fields = @{Bugzilla::Field->match({ obsolete => 0 })};
    # Exclude fields the user cannot query.
    if (!$user->is_timetracker) {
        @fields = grep { $_->name !~ /^(estimated_time|remaining_time|work_time|percentage_complete|deadline)$/ } @fields;
    }
    $vars->{'field'} = \@fields;

    $self->_bz_response_code(STATUS_OK);
    return $self->_result_from_template($vars);
}

##################
# Helper Methods #
##################

sub _result_from_template {
    my ($self, $vars) = @_;
    my $template = Bugzilla->template;

    $vars = $vars ? $vars : {};

    # Generate the configuration data.
    my $json;
    $template->process('config.json.tmpl', $vars, \$json)
      || ThrowTemplateError($template->error());
    my $result = $self->json->decode($json);

    return $result;
}

1;


