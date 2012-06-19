# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Install::Filesystem;

use Bugzilla::Extension::REST::Server;

our $VERSION = '0.01';

sub install_filesystem {
    my ($self,  $args) = @_;
    my $files = $args->{'files'};

    my $extensionsdir = bz_locations()->{'extensionsdir'};
    my $scriptname = $extensionsdir . "/" . __PACKAGE__->NAME . "/bin/rest.cgi";
 
    $files->{$scriptname} = {
        perms => Bugzilla::Install::Filesystem::WS_EXECUTE
    };

    # Add rewrite rule to root .htaccess file if not already included
    my $htaccess = new IO::File(".htaccess", 'r') || die ".htaccess: $!";
    my $htaccess_data;
    { local $/; $htaccess_data = <$htaccess>; }
    $htaccess->close;
    if ($htaccess_data !~ /RewriteRule rest\//) {
        print "Repairing .htaccess...\n";
        if ($htaccess_data !~ /RewriteEngine On/) {
            $htaccess_data .= "\nRewriteEngine On"; 
        }
        $htaccess_data .= "\nRewriteRule rest/(.*)\$ $scriptname/\$1 [NE]";
        $htaccess = new IO::File(".htaccess", 'w') || die $!;
        print $htaccess $htaccess_data;
        $htaccess->close;
    }
}

__PACKAGE__->NAME;
