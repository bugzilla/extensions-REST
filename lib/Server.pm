# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::Server;

use strict;

use base qw(Bugzilla::WebService::Server::JSONRPC);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::WebService::Constants;
use Bugzilla::WebService::Util qw(taint_data);
use Bugzilla::Util qw(correct_urlbase);

use Bugzilla::Extension::REST::View;
use Bugzilla::Extension::REST::Util;
use Bugzilla::Extension::REST::Constants;

use Data::Dumper; # DEBUG

#####################################
# Public JSON::RPC Method Overrides #
#####################################

sub handle {
    my ($self)  = @_;

    # Using current path information, decide which class/method to 
    # use to serve the request.
    $self->_load_resource($self->path_info);

    # Stop here if no resource matched 
    if (!$self->bz_method_name) {
        ThrowUserError("rest_invalid_resource");
    }

    # Dispatch to the proper module
    my $class  = $self->bz_class_name;
    my ($path) = $class =~ /::([^:]+)$/;
    $self->path_info($path);
    delete $self->{dispatch_path};
    $self->dispatch({ $path => $class });

    my $params = $self->_retrieve_json_params;

    #z Set callback name if exists
    $self->_bz_callback($params->{'callback'}) if $params->{'callback'};

    $self->_fix_credentials($params);

    # Fix includes/excludes for each call
    $params = fix_include_exclude($params);

    Bugzilla->input_params($params);

    # Set the JSON version to 1.1 and the id to the current urlbase
    # also set up the correct handler method
    my $obj = {};
    $obj->{'version'} = "1.1";
    $obj->{'id'}      = correct_urlbase();
    $obj->{'method'}  = $self->bz_method_name;
    $obj->{'params'}  = $params;

    # Execute the handler
    my $result = $self->_handle($obj);

    # Determine how the data should be represented
    $self->content_type($self->_best_content_type(ACCEPT_CONTENT_TYPES));
    
    if (!$self->error_response_header 
        && !(ref $result eq 'HASH' && exists $result->{'error'})) 
    {
        return $self->response(
            $self->response_header($self->bz_response_code, $result));
    }

    if (ref $result eq 'HASH' && exists $result->{'error'}) {
        $self->error_response_header(
            $self->response_header($self->bz_response_code, $result));
    }

    $self->response($self->error_response_header);
}

sub response {
    my ($self, $response) = @_;

    # If we have thrown an error, the 'error' key will exist
    # otherwise we use 'result'. JSONRPC returns other data
    # along with the result/error such as version and id which
    # we will strip off for REST calls.
    my $json_data = $self->json->decode($response->content);

    my $result;
    if (exists $json_data->{error}) {
        $result = $json_data->{error};
        # BzAPI sets error:true so we do the same
        $result->{error} = $self->type('boolean', 1);
    }
    else {
        $result = $json_data->{result};
    }

    # After converting the return data, encode it back into the proper content
    my $view = Bugzilla::Extension::REST::View->new($self->content_type);
    $response->content($view->view($result));

    $self->SUPER::response($response);
}

#######################################
# Bugzilla::WebService Implementation #
#######################################

sub handle_login {
    my $self = shift;

    # If we're being called using GET, we don't allow cookie-based or Env
    # login, because GET requests can be done cross-domain, and we don't
    # want private data showing up on another site unless the user
    # explicitly gives that site their username and password. (This is
    # particularly important for JSONP, which would allow a remote site
    # to use private data without the user's knowledge, unless we had this
    # protection in place.)
    if (!grep($_ eq $self->request->method, ('POST', 'PUT'))) {
        # XXX There's no particularly good way for us to get a parameter
        # to Bugzilla->login at this point, so we pass this information
        # around using request_cache, which is a bit of a hack. The
        # implementation of it is in Bugzilla::Auth::Login::Stack.
        Bugzilla->request_cache->{auth_no_automatic_login} = 1;
    }

    my $class = $self->bz_class_name;
    my $method = $self->bz_method_name;
    my $full_method = $class . "." . $method;
    $self->SUPER::handle_login($class, $method, $full_method);
}

######################################
# Private JSON::RPC Method Overrides #
######################################

# We do not want to run Bugzilla::WebService::Server::JSONRPC->_find_prodedure
# as it determines the method name differently.
sub _find_procedure {
    my $self = shift;
    return JSON::RPC::Server::_find_procedure($self, @_);
}

# This is a hacky way to do something right before methods are called.
# This is the last thing that JSON::RPC::Server::_handle calls right before
# the method is actually called.
sub _argument_type_check {
    my $self = shift;
    my $params = JSON::RPC::Server::_argument_type_check($self, @_);

    # JSON-RPC 1.0 requires all parameters to be passed as an array, so
    # we just pull out the first item and assume it's an object.
    my $params_is_array;
    if (ref $params eq 'ARRAY') {
        $params = $params->[0];
        $params_is_array = 1;
    }

    taint_data($params);

    Bugzilla->input_params($params);

    # Now, convert dateTime fields on input.
    my $method = $self->bz_method_name;
    my $pkg = $self->{dispatch_path}->{$self->path_info};
    my @date_fields = @{ $pkg->DATE_FIELDS->{$method} || [] };
    foreach my $field (@date_fields) {
        if (defined $params->{$field}) {
            my $value = $params->{$field};
            if (ref $value eq 'ARRAY') {
                $params->{$field} =
                    [ map { $self->datetime_format_inbound($_) } @$value ];
            }
            else {
                $params->{$field} = $self->datetime_format_inbound($value);
            }
        }
    }
    my @base64_fields = @{ $pkg->BASE64_FIELDS->{$method} || [] };
    foreach my $field (@base64_fields) {
        if (defined $params->{$field}) {
            $params->{$field} = decode_base64($params->{$field});
        }
    }

    # This is the best time to do login checks.
    $self->handle_login();

    # Bugzilla::WebService packages call internal methods like
    # $self->_some_private_method. So we have to inherit from 
    # that class as well as this Server class.
    my $new_class = ref($self) . '::' . $pkg;
    my $isa_string = 'our @ISA = qw(' . ref($self) . " $pkg)";
    eval "package $new_class;$isa_string;";
    bless $self, $new_class;

    if ($params_is_array) {
        $params = [$params];
    }

    return $params;
}

###################
# Utility Methods #
###################

sub bz_method_name {
    my ($self, $method) = @_;
    $self->{_bz_method_name} = $method if $method;
    return $self->{_bz_method_name}; 
}

sub bz_class_name {
    my ($self, $class) = @_;
    $self->{_bz_class_name} = $class if $class;
    return $self->{_bz_class_name};
}

sub bz_response_code {
    my ($self, $value) = @_;
    $self->{_bz_response_code} = $value if $value;
    return $self->{_bz_response_code};
}

sub bz_regex_matches {
    my ($self, $matches) = @_;
    $self->{_bz_regex_matches} = $matches if $matches;
    return $self->{_bz_regex_matches};
}

##########################
# Private Custom Methods #
##########################

sub _retrieve_json_params {
    my $self = shift;

    # Make a copy of the current input_params rather than edit directly
    my $params = {};
    %{$params} = %{ Bugzilla->input_params };

    # Merge any additional query key/values with $obj->{params} if not a GET request
    # We do this manually cause CGI.pm doesn't understand JSON strings.
    if ($self->request->method ne 'GET') {
        my $extra_params = {};
        my $json = delete $params->{'POSTDATA'} || delete $params->{'PUTDATA'};
        if ($json) {
            $extra_params = eval q| $self->json->decode($json) |;
            if ($@) {
                ThrowUserError('json_rpc_invalid_params', { err_msg  => $@ });
            }
        }
        %{$params} = (%{$params}, %{$extra_params}) if %{$extra_params};
    }

    return $params;
}

sub _load_resource {
    my ($self, $path) = @_;

    # Load in the Resource modules from extensions/REST/lib/Resources/*
    # and then call $module->resources to get the resources hash
    my $resources = {};
    my $resource_path = bz_locations()->{'extensionsdir'}. "/REST/lib/Resources";
    foreach my $item ((glob "$resource_path/*.pm")) {
        $item =~ m#/([^/]+)\.pm$#;
        my $module = "Bugzilla::Extension::REST::Resources::" . $1;
        eval("require $module") || die $@;
        $resources->{$module} = $module->resources; 
    }

    # Use the resources hash from each module loaded earlier to determine
    # which handler to use based on a regex match of the CGI path.
    # Also any matches found in the regex will be passed in later to the
    # handler for possible use.
    my $request_method = $self->request->method;
    my (@matches, $handler_found, $handler_method, $handler_class);
    foreach my $class (keys %{ $resources }) {
        foreach my $regex (keys %{ $resources->{$class} }) {
            if (@matches = ($path =~ $regex)) {
                if ($resources->{$class}{$regex}{$request_method}) {
                    $self->bz_class_name($class);
                    $self->bz_method_name($resources->{$class}{$regex}{$request_method});
                    $self->bz_regex_matches(\@matches);
                    $handler_found = 1;
                }
            }
            last if $handler_found;
        }
        last if $handler_found;
    }
}

sub _fix_credentials {
    my ($self, $params) = @_;
    # Allow user to pass in &username=foo&password=bar to login without cookies
    if ($params->{'username'} && $params->{'password'}) {
        $params->{'Bugzilla_login'} = $params->{'username'};
        $params->{'Bugzilla_password'} = $params->{'password'};
        delete $params->{'username'};
        delete $params->{'password'};
    }
}

sub _best_content_type {
    my ($self, @types) = @_;
    return ($self->_simple_content_negotiation(@types))[0] || '*/*';
}

sub _simple_content_negotiation {
    my ($self, @types) = @_;
    my @accept_types = $self->_get_content_prefs();
    my $score = sub { $self->_score_type(shift, @accept_types) };
    return sort {$score->($b) <=> $score->($a)} @types;
}

sub _score_type {
    my ($self, $type, @accept_types) = @_;
    my $score = scalar(@accept_types);
    for my $accept_type (@accept_types) {
        return $score if $type eq $accept_type;
        my $pat;
        ($pat = $accept_type) =~ s/([^\w*])/\\$1/g; # escape meta characters
        $pat =~ s/\*/.*/g; # turn it into a pattern
        return $score if $type =~ /$pat/;
        $score--;
    }
    return 0;
}

sub _get_content_prefs {
    my $self = shift;
    my $default_weight = 1;
    my @prefs;

    # Parse the Accept header, and save type name, score, and position.
    my @accept_types = split /,/, $self->_get_accept_header();
    my $order = 0;
    for my $accept_type (@accept_types) {
        my ($weight) = ($accept_type =~ /q=(\d\.\d+|\d+)/);
        my ($name) = ($accept_type =~ m#(\S+/[^;]+)#);
        next unless $name;
        push @prefs, { name => $name, order => $order++};
        if (defined $weight) {
            $prefs[-1]->{score} = $weight;
        } else {
            $prefs[-1]->{score} = $default_weight;
            $default_weight -= 0.001;
        }
    }

    # Sort the types by score, subscore by order, and pull out just the name
    @prefs = map {$_->{name}} sort {$b->{score} <=> $a->{score} || 
                                    $a->{order} <=> $b->{order}} @prefs;
    return @prefs, '*/*';  # Allows allow for */*
}

sub _get_accept_header {
    my $self = shift;
    return $self->cgi->http('accept') || "";
}

1;
