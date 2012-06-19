# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::REST::Resources::Bug;

use strict;

use base qw(Exporter Bugzilla::WebService Bugzilla::WebService::Bug);

use Bugzilla;
use Bugzilla::CGI;
use Bugzilla::Constants;
use Bugzilla::Search;
use Bugzilla::User;
use Bugzilla::Util qw(validate_email_syntax);
use Bugzilla::Error;

use Bugzilla::WebService::Util qw(filter_wants);

use Bugzilla::Extension::REST::Util;
use Bugzilla::Extension::REST::Constants;

use Tie::IxHash;
use Scalar::Util qw(blessed);
use List::MoreUtils qw(uniq);
use Data::Dumper; #DEBUG 

#############
# Resources #
#############

# IxHash keeps them in insertion order, and so we get regexp priorities right.
our $_resources = {};
tie(%$_resources, "Tie::IxHash",
    qr{/bug$} => { 
        GET  => 'bug_GET',
        POST => 'bug_POST',
    },
    qr{/bug/([^/]+)$} => {
        GET => 'one_bug_GET',
        PUT => 'bug_PUT',
    },
    qr{/bug/([^/]+)/comment$} => { 
        GET  => 'comment_GET',
        POST => 'comment_POST'  
    },
    qr{/bug/([^/]+)/history$}  => { 
        GET => 'history_GET'
    },
    qr{/bug/([^/]+)/attachment$} =>  {
        GET  => 'attachment_GET',
        POST => 'attachment_POST',
    },
    qr{/attachment/([^/]+)$} =>  {
        GET => 'one_attachment_GET'
    }, 
    qr{/bug/([^/]+)/flag$} => {
        GET => 'flag_GET',
    }, 
    qr{/count$} => {
        GET => 'count_GET', 
    }, 
    qr{/bug/comment/([^/]+)$} => {
        GET => 'comment_id_GET', 
    }
);

sub resources { return $_resources };

###########
# Methods #
###########

sub bug_GET {
    my ($self, $params) = @_;
    my $dbh = Bugzilla->dbh;

    my $bugs = $self->_do_search($params);

    $self->bz_response_code(STATUS_OK);
    return { bugs => $bugs };
}

# Return a single bug report
sub one_bug_GET {
    my ($self, $params) = @_;

    $params->{ids} = [ $self->bz_regex_matches->[0] ];
   
    my $result = $self->get($params);

    my $adjusted_bug = $self->_fix_bug($params, $result->{bugs}[0]);

    $self->bz_response_code(STATUS_OK);
    return $adjusted_bug;
}

# Update attributes of a single bug
sub bug_PUT {
    my ($self, $params) = @_;

    $params->{ids} = [ $self->bz_regex_matches->[0] ];

    my $result = $self->update($params);

    $self->bz_response_code(STATUS_OK);
    return { "ok" => 1 };
}

# Create a new bug
sub bug_POST {
    my ($self, $params) = @_;
    my $extra = {};

    # Downgrade user objects to email addresses
    foreach my $person ('assigned_to', 'reporter', 'qa_contact') {
        if ($params->{$person}) {
            $params->{$person} = $params->{$person}->{name};
        }
    }

    if ($params->{cc}) {
        my @names = map ( { $_->{name} } @{$params->{cc}});
        $params->{cc} = \@names;
    }

    # For consistency, we take initial comment in comments array
    delete $params->{description};
    if (ref $params->{comments}) {
        $params->{description} = $params->{comments}->[0]->{text};
        delete $params->{comments};
    }

    # Remove fields the XML-RPC interface will object to
    # We list legal fields rather than illegal ones because enumerating badness
    # breaks more easily. This list straight from the 3.4 documentation.
    my @legalfields = qw(product component summary version description 
                         op_sys platform priority severity alias assigned_to 
                         cc comment_is_private groups qa_contact status 
                         target_milestone);

    my @customfields = map { $_->name } Bugzilla->active_custom_fields;

    foreach my $field (keys %$params) {
        if (!grep($_ eq $field, (@legalfields, @customfields))) {
            $extra->{$field} = $params->{$field};
            delete $params->{$field};
        }
    }

    my $result = $self->create($params);

    my $bug_id = $result->{id};
    my $ref = ref_urlbase() . "/bug/$bug_id";

    # We do a Bug.update if we have any extra fields
    remove_immutables($extra);

    # We shouldn't have one of these, but let's not mid-air if they send one
    delete $extra->{last_change_time};

    if (%$extra) {
        $extra->{ids} = [ $bug_id ];
        $self->update($extra);
    }

    $self->bz_response_code(STATUS_CREATED);
    return { ref => $ref, id => $bug_id };
}

# Get all comments for given bug
sub comment_GET {
    my ($self, $params) = @_;

    my $bug_id = $self->bz_regex_matches->[0];
    $params->{ids} = [ $bug_id ];
    
    my $result = $self->comments($params);

    my @adjusted_comments = map { $self->_fix_comment($params, $_) }
                            @{ $result->{bugs}{$bug_id}{comments} };

    $self->bz_response_code(STATUS_OK);
    return { comments => \@adjusted_comments };
}

# Create a new comment for a given bug
sub comment_POST {
    my ($self, $params) = @_;
    my $bug_id = $self->bz_regex_matches->[0];
    $params->{id} = $bug_id;

    # Backwards compat
    $params->{comment} = $params->{text} if $params->{text};

    my $result = $self->add_comment($params);

    $self->bz_response_code(STATUS_OK);
    return { ref         => ref_urlbase() . "/bug/$bug_id/comment", 
             comment_ref => ref_urlbase() . "/bug/comment/" . $result->{id} }; 
}

# Get all history for a given bug
sub history_GET {
    my ($self, $params) = @_;

    my $bug_id = $self->bz_regex_matches->[0];
    $params->{ids} = [ $bug_id ];

    my $result = $self->history($params);

    my @adjusted_history;
    foreach my $changeset (@{ $result->{bugs}[0]{history} }) {
        $changeset->{bug_id} = $bug_id;
        push(@adjusted_history, $self->_fix_changeset($params, $changeset));
    }

    $self->bz_response_code(STATUS_OK);
    return { history => \@adjusted_history };
}

# Get attachments for a given bug
sub attachment_GET {
    my ($self, $params) = @_;

    my $bug_id = $self->bz_regex_matches->[0];
    $params->{ids} = [ $bug_id ];
    $params->{exclude_fields} = ['data']
        if !$params->{attachmentdata};

    my $result = $self->attachments($params);

    my @adjusted_attachments = map { $self->_fix_attachment($params, $_) } 
                               @{ $result->{bugs}{$bug_id} };

    $self->bz_response_code(STATUS_OK);
    return { attachments => \@adjusted_attachments };
}

# Get a single attachment
sub one_attachment_GET {
    my ($self,  $params) = @_;

    my $attach_id = $self->bz_regex_matches->[0];
    $params->{attachment_ids} = [ $attach_id ];
    $params->{exclude_fields} = ['data']
        if !$params->{attachmentdata};

    my $result = $self->attachments($params);

    my $adjusted_attachment 
        = $self->_fix_attachment($params, $result->{attachments}{$attach_id});

    $self->bz_response_code(STATUS_OK);
    return $adjusted_attachment;
}

# Create a new attachment for a given bug
sub attachment_POST {
    my ($self, $params) = @_;
    $self->bz_response_code(STATUS_CREATED);
    return $self->attachment($params);
}

# Get all currently set flags for a given bug
sub flag_GET {
    my ($self, $params) = @_;

    my $bug_id = $self->bz_regex_matches->[0];

    # Retrieve normal Bug flags
    my $bug = Bugzilla::Bug->check($bug_id);
    my $flags = $bug->flags;

    # Add any attachment flags as well
    foreach my $attachment (@{ $bug->attachments }) {
        push(@$flags, @{ $attachment->flags });
    }

    my @adjusted_flags 
        = map { $self->_fix_flag($params, $_) } @$flags;

    $self->bz_response_code(STATUS_OK);
    return { flags => \@adjusted_flags };
}

# Get a count of bugs based on the search paranms. If a x, y, or z
# axis if provided then return the counts as a chart.

sub count {
    my ($self, $params) = @_;

    my $col_field = delete $params->{x_axis_field};
    my $row_field = delete $params->{y_axis_field};
    my $tbl_field = delete $params->{z_axis_field};
   
    my $dimensions = $col_field ?
                     $row_field ?
                     $tbl_field ? 3 : 2 : 1 : 0;

    # Use bug status if no axis was provided
    if ($dimensions == 0) {
        $row_field = 'status';
    }
    elsif ($dimensions == 1) {
        # 1D *tables* should be displayed vertically (with a row_field only)
        $row_field = $col_field;
        $col_field = '';
    }

    # Call _do_search to get our bug list
    my $bugs = $self->_do_search($params);

    # We detect a numerical field, and sort appropriately, 
    # if all the values are numeric.
    my $col_isnumeric = 1;
    my $row_isnumeric = 1;
    my $tbl_isnumeric = 1;

    my (%data, %names);
    foreach my $bug (@$bugs) {
        # Values can be XMLRPC::Data types so we test for that
        my $row = $bug->{$row_field}; 
        my $col = $bug->{$col_field};
        my $tbl = $bug->{$tbl_field};

        $data{$tbl}{$col}{$row}++;
        $names{"col"}{$col}++;
        $names{"row"}{$row}++;
        $names{"tbl"}{$tbl}++;

        $col_isnumeric &&= ($col =~ /^-?\d+(\.\d+)?$/o);
        $row_isnumeric &&= ($row =~ /^-?\d+(\.\d+)?$/o);
        $tbl_isnumeric &&= ($tbl =~ /^-?\d+(\.\d+)?$/o);
    }

    my @col_names = @{_get_names($names{"col"}, $col_isnumeric, $col_field)};
    my @row_names = @{_get_names($names{"row"}, $row_isnumeric, $row_field)};
    my @tbl_names = @{_get_names($names{"tbl"}, $tbl_isnumeric, $tbl_field)};

    my @data;
    foreach my $tbl (@tbl_names) {
        my @tbl_data;
        foreach my $row (@row_names) {
            my @col_data;
            foreach my $col (@col_names) {
                $data{$tbl}{$col}{$row} = $data{$tbl}{$col}{$row} || 0;
                push(@col_data, $data{$tbl}{$col}{$row});
            }
            push(@tbl_data, \@col_data);
        }
        unshift(@data, \@tbl_data);
    }

    my $result;
    if ($dimensions == 0) {
        # Just return the sum of the counts if dimension == 0
        my $sum = 0;
        foreach my $list (@{ pop @data }) {
            $sum += $list->[0];
        }
        $result = {
            data => $sum,
        };
    }
    elsif ($dimensions == 1) {
        # Convert to a single list of counts if dimension == 1
        my @array;
        foreach my $list (@{ pop @data }) {
            push(@array, $list->[0]);
        }
        $result = {
            x_labels => \@row_names,
            data     => \@array || []
        };
    }
    elsif ($dimensions == 2) {
        $result = {
            x_labels => \@col_names,
            y_labels => \@row_names,
            data     => pop @data || [[]]
        };
    }
    elsif ($dimensions == 3) {
        $result = {
            x_labels => \@col_names,
            y_labels => \@row_names,
            z_labels => \@tbl_names,
            data     => @data ? \@data : [[[]]]
        };
    }

    $self->bz_response_code(STATUS_OK);
    return $result;
}

sub comment_id_GET {
    my ($self, $params) = @_;

    my $comment_id = $self->bz_regex_matches->[0];
    $params->{comment_ids} = [ $comment_id ];

    my $result = $self->comments($params);

    $self->bz_response_code(STATUS_OK);
    return $self->_fix_comment($params, $result->{comments}{$comment_id});
}

##################
# Helper Methods #
##################

sub _do_search {
    my ($self, $params) = @_;

    print STDERR Dumper $params;

    $params->{bug_id} = $params->{id} if exists $params->{id};

    my $cgi = Bugzilla::CGI->new($params);

    # make sure we were passed some search params
    if (length $cgi->query_string == 0) {
        ThrowUserError("buglist_parameters_required");
    }
    if (!Bugzilla->params->{'specific_search_allow_empty_words'}
        && defined $cgi->param('content') && $cgi->param('content') =~ /^\s*$/)
    {
        ThrowUserError("buglist_parameters_required");
    }
    $cgi->clean_search_url();
    if (!$cgi->param) {
        ThrowUserError("buglist_parameters_required");
    }

    my $search = new Bugzilla::Search('fields' => ['bug_id'],
                                      'params' => $cgi);
    my $query = $search->getSQL(); 

    my $dbh = Bugzilla->switch_to_shadow_db();

    my $bugids = $dbh->selectcol_arrayref($query);

    my @bugs;
    foreach my $id (@$bugids) {
        $params->{ids} = [ $id ];
        my $result = $self->get($params);
        push(@bugs, $result->{bugs}[0]);
    }

    my @adjusted_bugs = map { $self->_fix_bug($params, $_) } @bugs;

    return \@adjusted_bugs;
}

sub _fix_bug {
    my ($self, $params, $bug) = @_;

    foreach my $field (qw(assigned_to reporter qa_contact creator)) {
        $bug->{$field} = $self->_fix_person($bug->{$field});
    }

    my @tmp_cc;
    foreach my $cc (@{$bug->{cc}}) {
        next if !$cc;
        push(@tmp_cc, $self->_fix_person($cc));
    }
    $bug->{cc} = \@tmp_cc;

    # Add in attachment meta data
    if (filter_wants $params, 'attachments') {
        my $attach_params = { ids => [ $bug->{id} ] };
        $attach_params->{exclude_fields} = ['data'] 
            unless $params->{attachmentdata};

        my $attachments = $self->attachments($attach_params);

        $bug->{attachments} 
            = [ map { $self->_fix_attachment($attach_params, $_) } 
                @{ $attachments->{bugs}{$bug->{id}} } ];
    }

    $bug->{ref} = ref_urlbase() . "/bug/" . $bug->{id};

    return $bug;    
}

sub _fix_person {
    my ($self, $login) = @_;
    my $user_hash;
    if (validate_email_syntax($login) && Bugzilla->user->id) {
        my $user = Bugzilla::User->new({ name => $login });
        $user_hash = { name      => $user->login,
                       real_name => $user->name,   
                       ref       => ref_urlbase . "/user/" . $user->login };    
    }
    else {
        $user_hash = { name => Bugzilla::Util::email_filter($login) };
    } 
    return $user_hash;
}

sub _fix_comment {
    my ($self, $params, $comment) = @_;

    $comment->{creator} = {
        ref => ref_urlbase() . "/user/" . $comment->{creator}, 
        name => $comment->{creator}
    };
    $comment->{creation_time} = $comment->{time};

    delete $comment->{author};
    delete $comment->{time};
    delete $comment->{attachment_id};

    $comment->{bug_ref} = ref_urlbase() . "/bug/" . $comment->{bug_id};
    $comment->{comment_ref} = ref_urlbase() . "/bug/comment/" . $comment->{id};
                                 
    return $comment;
}

sub _fix_changeset {
    my ($self, $params, $changeset) = @_;

    $changeset->{changer} = {
        ref => ref_urlbase() . "/user/" . $changeset->{who},
        name => $changeset->{who}
    };
    $changeset->{change_time} = $changeset->{when};

    delete $changeset->{who};
    delete $changeset->{when};

    $changeset->{bug_ref} = ref_urlbase() . "/bug/" . $changeset->{bug_id};

    return $changeset;
}

sub _fix_attachment {
    my ($self, $params, $attachment) = @_;

    $attachment->{attacher} = {
         ref  => ref_urlbase() . "/user/" . $attachment->{attacher},
         name => $attachment->{attacher}
    };

    $attachment->{is_patch}    = $self->type('boolean', $attachment->{is_patch});
    $attachment->{is_private}  = $self->type('boolean', $attachment->{is_private});
    $attachment->{is_obsolete} = $self->type('boolean', $attachment->{is_obsolete});
    $attachment->{is_url}      = $self->type('boolean', $attachment->{is_url});

    if ($attachment->{flags}) {
        $attachment->{flags} 
            = [ map { $self->_fix_flag($params, $_) } @{ $attachment->{flags} } ];
    }

    $attachment->{bug_ref}  = ref_urlbase() . "/bug/" . $attachment->{bug_id};
    $attachment->{ref}      = ref_urlbase() . "/attachment/" . $attachment->{id};
 
    return $attachment; 
}

sub _fix_flag {
    my ($self, $params, $flag) = @_;

    my $setter = blessed $flag ? $flag->setter->login : $flag->{setter};
    $flag->{setter} = $self->_fix_person($setter);

    if ($flag->{requestee_id}) {
        my $requestee = blessed $flag ? $flag->requestee->login : $flag->{requestee};
        $flag->{requestee} = $self->_fix_person($requestee);
    }

    $flag->{name} = blessed $flag ? $flag->name : $flag->{name};

    delete $flag->{type};
    delete $flag->{attach_id} if !$flag->{attach_id};
    delete $flag->{setter_id};
    delete $flag->{requestee_id};

    $flag->{bug_ref} = ref_urlbase() . "/bug/" . $flag->{bug_id};

    return $flag;
}

sub _get_names {
    my ($names, $isnumeric, $field) = @_;
 
    my $select_fields = Bugzilla->fields({ is_select => 1 });
   
    my %fields;
    foreach my $field (@$select_fields) {
        my @names = map { $_->name } Bugzilla::Field::Choice->type($field)->get_all();
        unshift @names, ' ' if $field->name eq 'resolution'; 
        $fields{$field->name} = [ uniq @names ];
    } 
    
    my $field_list = $fields{$field};
    
    my @sorted;
    if ($field_list) {
        my @unsorted = keys %{$names};
        foreach my $item (@$field_list) {
            push(@sorted, $item) if grep { $_ eq $item } @unsorted;
        }
    }  
    elsif ($isnumeric) {
        sub numerically { $a <=> $b }
        @sorted = sort numerically keys(%{$names});
    } else {
        @sorted = sort(keys(%{$names}));
    }
    
    return \@sorted;
}

1;

__END__

=head1 NAME

Bugzilla::Extension::REST::Resources::Bug - The API for creating, 
changing, and getting the details of bugs.

=head1 DESCRIPTION

This part of the Bugzilla API allows you to file a new bug in Bugzilla,
or get information about bugs that have already been filed.

=head1 RESOURCES

=head2 Retrieve a bug (/bug/<bug_id> GET)

=over

=item B<Arguments>

The bug id is provided in the URL. Extra arguments are in the form of ?arg1=value1&arg2=value2...
Includes flags, CC list, related bugs and attachment metadata by default. Does not include 
attachment data, comments or history - so amount of data is bounded (use field control such as 
include_fields to get them). 

=back 

=item B<Response>

=over

Returns a Bug Object containing the bug's attributes.

Bug Object:

=item C<actual_time>     Decimal, Read Only  Time it has taken to fix the bug so far     
=item C<alias>   String  Bug's alias (text alternative to ID)    
=item C<assigned_to     User    User responsible for the bug    
=item C<attachments     Array of Attachment     Related files stored by Bugzilla    attachment
=item C<blocks  Array of Integer    IDs of bugs which can only be fixed after this one  blocked
=item C<cc  Array of User   Users signed up to be notified of changes   
=item C<classification  String  Name of classification (categorization above product)   
=item C<comments    Array of Comment    Things people have said about the bug   long_desc
=item C<component   String  Bug's component (sub-product)   
=item C<creation_time   Timestamp String, Read Only     When bug was filed  creation_ts, opendate
=item C<creator     User, Read Only     User who submitted the bug  reporter
=item C<deadline    Datestamp String    Date by which bug must be fixed     
=item C<depends_on  Array of Integer    Bugs that must be fixed first   dependson
=item C<dupe_of     Integer     Bug number of which this bug is a duplicate (only present if bug is RESOLVED DUPLICATE)     
=item C<estimated_time  Decimal     Current estimated time for fix, in hours    
=item C<flags   Array of Flag   Flags set on this bug   
=item C<groups  Array of Group  Groups to which this bug belongs    
=item C<history     Array of ChangeSet, Read Only   Changes made to bug fields in the past (requires 3.4)   
=item C<id  Integer, Read Only  Unique numeric identifier for bug   bug_id
=item C<is_cc_accessible    Boolean     Whether CC list can see bug, regardless of groups   cclist_accessible
=item C<is_confirmed    Boolean, Read Only  Whether bug has ever passed from UNCONFIRMED to CONFIRMED status    everconfirmed, is_everconfirmed
=item C<is_creator_accessible   Boolean     Whether creator (reporter) can see bug, regardless of groups    reporter_accessible, is_reporter_accessible
=item C<keywords    Array of String     Tags (from a limited set) describing the bug    
=item C<last_change_time    Timestamp String, Read Only     Last change     delta_ts, changeddate
=item C<op_sys  String  Operating system bug was seen on, e.g. Windows Vista, Linux     
=item C<platform    String  Computing platform bug was seen on, e.g. PC, Mac    rep_platform
=item C<priority    String  How important the bug is, e.g. P1, P5   
=item C<product     String  Name of product     
=item C<qa_contact  User    User responsible for checking bug is fixed  
=item C<ref     String, Read Only   URL of bug in API   
=item C<remaining_time  Decimal, Read Only  Hours left before fix will be done  
=item C<resolution  String  The resolution, if the bug is in a closed state, e.g. FIXED, DUPLICATE  
=item C<see_also    Array of String     URLs of related bugs    
=item C<severity    String  How severe the bug is, e.g. enhancement, critical   bug_severity
=item C<status  String  Current status, e.g. NEW, RESOLVED  bug_status
=item C<summary     String  Short sentence describing the bug   short_desc
=item C<target_milestone    String  When the bug is going to be fixed   
=item C<update_token    String  Token you'll need to submit to change the bug; supplied only when logged in     token
=item C<url     String  URL relating to the bug (in search defaults only on 4.0 and above)  bug_file_loc
=item C<version     String  Version of software in which bug is seen    
=item C<whiteboard  String  Notes on current status     status_whiteboard
=item C<work_time   Decimal (Submit Only)   Hours to be added to actual_time    

    F
=back

=head2 List comments for bug (/bug/<bug_id>/comment GET)

=over

=item B<Arguments>

The bug id is provided in the URL. Extra arguments are in the form of ?arg1=value1&arg2=value2... 

=over 

=item C<new_since> (string) DateTime parameter (YYYYMMDDTHHMMSS format only) 
returns only ones since date given.

=back

=item B<Response>

=over

=item C<comments> (array) A list of hashes containing comment objects (see below).

=back

Comment Object:

=over

=item C<bug_ref> (string) Reference link to the bug the comment belongs to

=item C<comment_ref> (string) Reference link to this comment

=item C<attachment_id> (int) ID of attachment added at the same time as this comment, if any.
    
=item C<attachment_ref> (string) Ref of attachment added at the same time as this comment, if any.
 
=item C<creator> (UserObject) User who wrote the comment

=item C<creation_time> (string) Timestamp comment was added  

=item C<id> (int) Unique numeric identifier for comment 

=item C<is_private> (boolean) Whether comment is private or not

=item C<text> (string) Text of comment (plain text with no linkification)

=back

=item B<Notes>

* Example: [https://api-dev.bugzilla.mozilla.org/latest/bug/350001/comment bug 350001 comments].
* No comments (or none you can see) -> empty array.

=back 

=head2 Get a single comment for bug based on comment id (/bug/comment/<comment_id> GET)

=over

=item B<Arguments>

None. Comment ID is embedded in the URL string.

=item B<Response>

Returns hash containing a comment object.

=item B<Notes>

* Example: [https://api-dev.bugzilla.mozilla.org/latest/bug/350001/comment bug 350001 comments].
* No comments (or none you can see) -> empty array.

=back

=head2 Add new comment to bug (/bug/<id>/comment POST)

=over

=item B<Arguments>

Comment data as POST body.

=over

=item C<is_private> (boolean) Whether comment is private or not

=item C<text> (string) Text of comment (plain text with no linkification)

=back

=item B<Response>

201 Created status code, Location header pointing to bug/<id>/comment (as individual comments don't have their own location).

=over

=item C<ref> (string) Reference link to the bug that the comment belongs to. Same as location header.

=item C<comment_ref> (string) Reference link to the actual comment just added.

=back

=item B<Notes>

Unconditional - no conflict checking 

=back
