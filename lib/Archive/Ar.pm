###########################################################
#    Archive::Ar - Pure perl module to handle ar achives
#    
#    Copyright 2003 - Jay Bonci <jaybonci@cpan.org>
#    Copyright 2014 - John Bazik <jbazik@cpan.org>
#    Licensed under the same terms as perl itself
#
###########################################################
package Archive::Ar;

use base qw(Exporter);
our @EXPORT_OK = qw(COMMON BSD GNU);

use strict;
use File::Spec;
use Time::Local;
use Carp qw(carp longmess);

use vars qw($VERSION);
$VERSION = '2.00';

use constant CAN_CHOWN => ($> == 0 and $^O ne 'MacOS' and $^O ne 'MSWin32');

use constant ARMAG => "!<arch>\n";
use constant SARMAG => length(ARMAG);
use constant ARFMAG => "`\n";
use constant AR_EFMT1 => "#1/";

use constant COMMON => 1;
use constant BSD => 2;
use constant GNU => 3;

my $has_io_string;
BEGIN {
    $has_io_string = eval {
        require IO::String;
        import IO::String;
    } || 0;
}

sub new {
    my $class = shift;
    my $file = shift;
    my $opts = shift || {};
    my $self = bless {}, $class;
    my $defopts = {chmod => 1};

    $self->clear();
    $self->{opts} = {(%$defopts, %{ref $opts ? $opts : {warn => 1}})};
    if ($file) {
        return unless $self->read($file);
    }
    return $self;
}

sub set_opt {
    my $self = shift;
    my $name = shift;
    my $val = shift;

    $self->{opts}->{$name} = $val;
}

sub get_opt {
    my $self = shift;
    my $name = shift;

    return $self->{opts}->{$name};
}

sub type {
    return shift->{type};
}

sub clear {
    my $self = shift;

    $self->{names} = [];
    $self->{files} = {};
    $self->{type} = undef;
}

sub read {
    my $self = shift;
    my $file = shift;

    my $fh = $self->_get_handle($file);
    local $/ = undef;
    my $data = <$fh>;
    close $fh;
        
    return $self->read_memory($data);
}

sub read_memory {
    my $self = shift;
    my $data = shift;

    $self->clear();
    return unless $self->_parse($data);
    return length($data);
}

sub contains_file {
    my $self = shift;
    my $filename = shift;

    return unless defined $filename;
    return exists $self->{files}->{$filename};
}

sub extract {
    my $self = shift;

    for my $filename (@_ or @{$self->{names}}) {
        $self->extract_file($filename) or return;
    }
    return 1;
}

sub extract_file {
    my $self = shift;
    my $filename = shift;
    my $target = shift || $filename;

    my $meta = $self->{files}->{$filename};
    return $self->_error("$filename: not in archive") unless $meta;
    open my $fh, '>', $target or return $self->_error("$target: $!");
    binmode $fh;
    syswrite $fh, $meta->{data} or return $self->_error("$filename: $!");
    close $fh or return $self->_error("$filename: $!");
    if (CAN_CHOWN) {
        chown $meta->{uid}, $meta->{gid}, $filename or
					return $self->_error("$filename: $!");
    }
    if ($self->{opts}->{chmod}) {
        my $mode = $meta->{mode};
        if ($self->{opts}->{perms}) {
            $mode &= ~(oct(7000) | umask);
        }
        chmod $mode, $filename or return $self->_error("$filename: $!");
    }
    utime $meta->{date}, $meta->{date}, $filename or
					return $self->_error("$filename: $!");
    return 1;
}

sub rename {
    my $self = shift;
    my $filename = shift;
    my $target = shift;

    if ($self->{files}->{$filename}) {
        $self->{files}->{$target} = $self->{files}->{$filename};
        delete $self->{files}->{$filename};
        for (@{$self->{names}}) {
            if ($_ eq $filename) {
                $_ = $target;
                last;
            }
        }
    }
}

sub chmod {
    my $self = shift;
    my $filename = shift;
    my $mode = shift;	# octal string or numeric

    return unless $self->{files}->{$filename};
    $self->{files}->{$filename}->{mode} =
                                    $mode + 0 eq $mode ? $mode : oct($mode);
    return 1;
}

sub chown {
    my $self = shift;
    my $filename = shift;
    my $uid = shift;
    my $gid = shift;

    return unless $self->{files}->{$filename};
    $self->{files}->{$filename}->{uid} = $uid;
    $self->{files}->{$filename}->{gid} = $gid if defined $gid;
    return 1;
}

sub remove {
    my $self = shift;
    my $files = ref $_[0] ? shift : \@_;

    my $nfiles_orig = scalar @{$self->{names}};

    for my $file (@$files) {
        next unless $file;
        if (exists($self->{files}->{$file})) {
            delete $self->{files}->{$file};
        }
        else {
            $self->_error("$file: no such member")
        }
    }
    @{$self->{names}} = grep($self->{files}->{$_}, @{$self->{names}});

    return $nfiles_orig - scalar @{$self->{names}};
}

sub list_files {
    my $self = shift;

    return wantarray ? @{$self->{names}} : $self->{names};
}

sub add_files {
    my $self = shift;
    my $files = ref $_[0] ? shift : \@_;

    for my $path (@$files) {
        if (open my $fd, $path) {
            my @st = stat $fd or return $self->_error("$path: $!");
            local $/ = undef;
            binmode $fd;
            my $content = <$fd>;
            close $fd;

            my $filename = (File::Spec->splitpath($path))[2];

            $self->_add_data($filename, $content, @st[9,4,5,2,7]);
        }
        else {
            $self->_error("$path: $!");
        }
    }
    return scalar @{$self->{names}};
}

sub add_data {
    my $self = shift;
    my $path = shift;
    my $content = shift;
    my $params = shift || {};

    return $self->_error("No filename given") unless $path;

    my $filename = (File::Spec->splitpath($path))[2];

    $self->_add_data($filename, $content,
                     $params->{date} || timelocal(localtime()),
                     $params->{uid} || 0,
                     $params->{gid} || 0,
                     $params->{mode} || 0100644) or return;

    return $self->{files}->{$filename}->{size};
}

sub write {
    my $self = shift;
    my $filename = shift;
    my $opts = {(%{$self->{opts}}, %{shift || {}})};
    my $type = $opts->{type} || $self->{type} || COMMON;

    my @body = ( ARMAG );

    my %gnuindex;
    my @filenames = @{$self->{names}};
    if ($type eq GNU) {
        #
        # construct extended filename index, if needed
        #
        if (my @longs = grep(length($_) > 15, @filenames)) {
            my $ptr = 0;
            for my $long (@longs) {
                $gnuindex{$long . '/'} = $ptr;
                $ptr += length($long) + 2;
            }
            push @body, pack('A16A32A10A2', '//', '', $ptr, ARFMAG),
                        join("/\n", @longs, '');
        }
    }
    for my $fn (@filenames) {
        my $meta = $self->{files}->{$fn};
        my $mode = sprintf('%o', $meta->{mode});
        my $size = $meta->{size};

        $fn .= '/' if $type eq GNU;

        if (length($fn) <= 16 || $type eq COMMON) {
            push @body, pack('A16A12A6A6A8A10A2', $fn,
                              @$meta{qw/date uid gid/}, $mode, $size, ARFMAG);
        }
        elsif ($type eq GNU) {
            push @body, pack('A1A15A12A6A6A8A10A2', '/', $gnuindex{$fn},
                              @$meta{qw/date uid gid/}, $mode, $size, ARFMAG);
        }
        elsif ($type eq BSD) {
            $size += length($fn);
            push @body, pack('A3A13A12A6A6A8A10A2', AR_EFMT1, length($fn),
                              @$meta{qw/date uid gid/}, $mode, $size, ARFMAG),
                        $fn;
        }
        else {
            return $self->_error("$type: unexpected ar type");
        }
        push @body, $meta->{data};
        push @body, "\n" if $size % 2; # padding
    }
    if ($filename) {
        my $fh = $self->_get_handle($filename, '>');
        print $fh @body;
        close $fh;
        my $len = 0;
        $len += length($_) for @body;
        return $len;
    }
    else {
        return join '', @body;
    }
}

sub get_content {
    my $self = shift;
    my ($filename) = @_;

    unless ($filename) {
        $self->_error("get_content can't continue without a filename");
        return;
    }

    unless (exists($self->{files}->{$filename})) {
        $self->_error(
                "get_content failed because there is not a file named $filename");
        return;
    }

    return $self->{files}->{$filename};
}

sub get_data {
    my $self = shift;
    my $filename = shift;

    return $self->_error("$filename: no such member")
			unless exists $self->{files}->{$filename};
    return $self->{files}->{$filename}->{data};
}

sub get_handle {
    my $self = shift;
    my $filename = shift;
    my $fh;

    return $self->_error("$filename: no such member")
			unless exists $self->{files}->{$filename};
    if ($has_io_string) {
        $fh = IO::String->new($self->{files}->{$filename}->{data});
    }
    else {
        open $fh, \$self->{files}->{$filename}->{data} or
			return $self->_error("in-memory file: $!");
    }
    return $fh;
}

sub error {
    my $self = shift;

    return shift() ? $self->{longmess} : $self->{error};
}

#
# deprecated
#
sub DEBUG {
    my $self = shift;
    my $debug = shift;

    $self->{opts}->{warn} = 1 unless (defined($debug) and int($debug) == 0);
}

sub _parse {
    my $self = shift;
    my $data = shift;

    unless (substr($data, 0, SARMAG, '') eq ARMAG) {
        return $self->_error("Bad magic number - not an ar archive");
    }
    my $type;
    my $names;
    while ($data =~ /\S/) {
        my ($name, $date, $uid, $gid, $mode, $size, $magic) =
                    unpack('A16A12A6A6A8A10a2', substr($data, 0, 60, ''));
        unless ($magic eq "`\n") {
            return $self->_error("Bad file header");
        }
        if ($name =~ m|^/|) {
            $type = GNU;
            if ($name eq '//') {
                $names = substr($data, 0, $size, '');
                next;
            }
            else {
                $name = substr($names, int(substr($name, 1)));
                $name =~ s/\n.*//;
                chop $name;
            }
        }
        elsif ($name =~ m|^#1/|) {
            $type = BSD;
            $name = substr($data, 0, int(substr($name, 3)), '');
            $size -= length($name);
        }
        else {
            if ($name =~ m|/$|) {
                $type ||= GNU;	# only gnu has trailing slashes
                chop $name;
            }
        }
        $uid = int($uid);
        $gid = int($gid);
        $mode = oct($mode);
        my $content = substr($data, 0, $size, '');
        substr($data, 0, $size % 2, '');

        $self->_add_data($name, $content, $date, $uid, $gid, $mode, $size);
    }
    $self->{type} = $type || COMMON;
    return scalar @{$self->{names}};
}

sub _add_data {
    my $self = shift;
    my $filename = shift;
    my $content = shift || '';
    my $date = shift || timelocal(localtime());
    my $uid = shift || 0;
    my $gid = shift || 0;
    my $mode = shift || 0100644;
    my $size = shift || length($content);

    if (exists($self->{files}->{$filename})) {
        return $self->_error("$filename: entry already exists");
    }
    $self->{files}->{$filename} = {
        name => $filename,
        date => $date,
        uid => $uid,
        gid => $gid,
        mode => $mode,
        size => $size,
        data => $content,
    };
    push @{$self->{names}}, $filename;
    return 1;
}

sub _get_handle {
    my $self = shift;
    my $file = shift;
    my $mode = shift || '<';

    if (ref $file) {
        return $file if eval{*$file{IO}} or $file->isa('IO::Handle');
        return $self->_error("Not a filehandle");
    }
    else {
        open my $fh, $mode, $file or return $self->_error("$file: $!");
        binmode $fh;
        return $fh;
    }
}

sub _error {
    my $self = shift;
    my $msg = shift;

    $self->{error} = $msg;
    $self->{longerror} = longmess($msg);
    if ($self->{opts}->{debug}) {
        carp $self->{longerror};
    }
    elsif ($self->{opts}->{warn}) {
        carp $self->{error};
    }
    return;
}

1;

__END__

=head1 NAME

Archive::Ar - Interface for manipulating ar archives

=head1 SYNOPSIS

    use Archive::Ar;

    my $ar = Archive::Ar->new;

    $ar->read('./foo.ar');
    $ar->extract;

    $ar->add_files('./bar.tar.gz', 'bat.pl')
    $ar->add_data('newfile.txt','Some contents');

    $ar->chmod('file1', 0644);
    $ar->chown('file1', $uid, $gid);

    $ar->remove('file1', 'file2');

    my $filehash = $ar->get_content('bar.tar.gz');
    my $data = $ar->get_data('bar.tar.gz');
    my $handle = $ar->get_handle('bar.tar.gz');

    my @files = $ar->list_files();

    my $archive = $ar->write;
    my $size = $ar->write('outbound.ar');

    $ar->error();


=head1 DESCRIPTION

Archive::Ar is a pure-perl way to handle standard ar archives.  

This is useful if you have those types of archives on the system, but it 
is also useful because .deb packages for the Debian GNU/Linux distribution are 
ar archives. This is one building block in a future chain of modules to build, 
manipulate, extract, and test debian modules with no platform or architecture 
dependence.

You may notice that the API to Archive::Ar is similar to Archive::Tar, and
this was done intentionally to keep similarity between the Archive::*
modules.

=head2 Object Methods

=over 4

=item * C<new()>

=item * C<new(I<$filename>)>

=item * C<new(I<$filehandle>)>

Returns a new Archive::Ar object.  Without an argument, it returns
an empty object.  If passed a filename or an open filehandle, it will
read the referenced archive into memory.  If the read fails for any
reason, returns undef.

=back

=over 4

=item * C<get_ar_type()>

Returns the type of the ar archive.  The type is undefined until an
archive is loaded.  If the archive displays characteristics of a gnu-style
archive, GNU is returned.  If it looks like a bsd-style archive, BSD
is returned.  Otherwise, COMMON is returned.  Note that unless filenames
exceed 16 characters in length, bsd archives look like the common format.

=back

=over 4

=item * C<clear()>

Clears the current in-memory archive.

=back

=over 4

=item * C<read(I<$filename>)>

=item * C<read(I<$filehandle>)>;

This reads a new file into the object, removing any ar archive already
represented in the object.  The argument may be a filename, filehandle
or IO::Handle object.

=back

=over 4

=item * C<read_memory(I<$data>)>

Parses the string argument as an archive, reading it into memory.  Replaces
any previously loaded archive.  Returns the number of bytes read, or undef
if it fails.

=back

=over 4

=item * C<contains_file(I<$filename>)>

Returns true if the archive contains a file with $filename.  Returns
undef otherwise.

=back

=over 4

=item * C<extract()>

=item * C<extract_file(I<$filename>)>

Extracts files from the archive.  The first form extracts all files, the
latter extracts just the named file.  Extracted files are assigned the
permissions and modification time stored in the archive, and, if possible,
the user and group ownership.  Returns non-zero upon success, or undef if
failure.

=back

=over 4

=item * C<rename(I<$filename>, I<$newname>)>

Changes the name of a file in the in-memory archive.

=back

=over 4

=item * C<remove(I<@filenames>)>

=item * C<remove(I<$arrayref>)>

Removes files from the in-memory archive.  Returns the number of files
removed.

=back

=over 4

=item * C<list_files()>

Returns a list of the names of all the files in the archive.
If called in a scalar context, returns a reference to an array.

=back

=over 4

=item * C<add_files(I<@filenames>)>

=item * C<add_files(I<$arrayref>)>

Adds files to the archive.  The arguments can be paths, but only the
filenames are stored in the archive.  Stores the uid, gid, mode, size,
and modification timestamp of the file as returned by C<stat()>.

Returns the number of files successfully added, or undef if failure.

=back

=over 4

=item * C<add_data(I<"filename">, I<$data>, [I<$optional_hashref>])>

Adds a file to the in-memory archive with name $filename and content
$data.  File properties can be set with $optional_hashref:

    $optional_hashref = {
        'data' => $data,
        'uid' => $uid, #defaults to zero
        'gid' => $gid, #defaults to zero
        'date' => $date,  #date in epoch seconds. Defaults to now.
        'mode' => $mode, #defaults to 0100644;
    }

You cannot add_data over another file however.  This returns the file length in 
bytes if it is successful, undef otherwise.

=back

=over 4


=item * C<write()>

=item * C<write(I<$filename>)>

Returns the archive as a string, or writes it to disk as $filename.
Returns the archive size upon success when writing to disk.  Returns
undef if failure.

=back

=over 4

=item * C<get_content(I<$filename>)>

This returns a hash with the file content in it, including the data
that the file would contain.  If the file does not exist or no filename
is given, this returns undef. On success, a hash is returned:

    $returned_hash = {
        'name' => $filename,
        'date' => $mtime,
        'uid' => $uid,
        'gid' => $gid,
        'mode' => $mode,
        'size' => $size,
        'data' => $file_contents,
    }

=back

=over 4

=item * C<get_data(I<"filename">)>

Returns a scalar containing the file data of the given archive
member.  Upon error, returns undef.

=back

=over 4

=item * C<get_handle(I<"filename">)>

Returns a file handle to the in-memory file data of the given archive member.
Upon error, returns undef.  This can be useful for unpacking nested archives.
Uses IO::String if it's loaded.

=back

=over 4

=item * C<error(I<$trace>)>

Returns the current error string, which is usually the last error reported.
If a true value is provided, returns the error message and stack trace.

=back

=head1 BUGS

See https://github.com/jbazik/Archive-Ar/issues/ to report and view bugs.

=head1 SOURCE

The source code repository for Archive::Ar can be found at http://github.com/jbazik/Archive-Ar/.

=head1 COPYRIGHT

Copyright 2009-2014 John Bazik E<lt>jbazik@cpan.orgE<gt>.

Copyright 2003 Jay Bonci E<lt>jaybonci@cpan.orgE<gt>. 

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
