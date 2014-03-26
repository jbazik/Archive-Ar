package Archive::Ar;

###########################################################
#    Archive::Ar - Pure perl module to handle ar achives
#    
#    Copyright 2003 - Jay Bonci <jaybonci@cpan.org>
#    Licensed under the same terms as perl itself
#
###########################################################

use strict;
use Exporter;
use File::Spec;
use Time::Local;
use Carp qw(carp longmess);

use vars qw($VERSION);
$VERSION = '1.17';

use constant ARMAG => "!<arch>\n";
use constant SARMAG => length(ARMAG);
use constant ARFMAG => "`\n";

sub new {
    my $class = shift;
    my $filenameorhandle = shift;
    my $self = bless {}, $class;

    $self->_initValues();

    $self->DEBUG if shift;	# backward compatibility

    if ($filenameorhandle) {
        unless ($self->read($filenameorhandle)) {
            $self->_error("new() failed on filename or filehandle read");
            return;
        }        
    }
    return $self;
}

sub read {
    my $self = shift;
    my ($filenameorhandle) = @_;

    my $retval;

    $self->_initValues();

    if (ref $filenameorhandle eq "GLOB") {
        unless ($retval = $self->_readFromFilehandle($filenameorhandle)) {
            $self->_error("Read from filehandle failed");
            return;
        }
    }
    else {
        unless ($retval = $self->_readFromFilename($filenameorhandle)) {
            $self->_error("Read from filename failed");
            return;
        }
    }

    unless ($self->_parseData()) {
        $self->_error(
                "read() failed on data structure analysis. Probable bad file");
        return; 
    }
    return $retval;
}

sub read_memory {
    my $self = shift;
    my ($data) = @_;

    $self->_initValues();

    unless ($data) {
        $self->_error("read_memory() can't continue because no data was given");
        return;
    }

    $self->{_filedata} = $data;

    unless ($self->_parseData()) {
        $self->_error(
            "read_memory() failed on data structure analysis. Probable bad file");
        return;
    }
    return length($data);
}

sub remove {
    my $self = shift;
    my $files = ref $_[0] ? shift : \@_;

    my $filecount = 0;

    for my $file (@$files) {
        $filecount += $self->_remFile($file);
    }
    return $filecount;
}

sub list_files {
    my $self = shift;

    return wantarray ? @{$self->{_files}} : $self->{_files};
}

sub add_files {
    my $self = shift;
    my $files = ref $_[0] ? shift : \@_;
    
    my $filecount = 0;

    for my $filename (@$files) {
        my @props = stat($filename);
        unless (@props) {
            $self->_error(
               "Could not stat() filename. add_files() for this file failed");
            next;
        }
        my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = @props;  
        
        my $header = {
            "date" => $mtime,
            "uid"  => $uid,
            "gid"  => $gid, 
            "mode" => $mode,
            "size" => $size,
        };

        local $/ = undef;
        unless (open HANDLE, $filename) {
            $self->_error(
                    "Could not open filename. add_files() for this file failed");
            next;
        }
        binmode HANDLE;
        $header->{data} = <HANDLE>;
        close HANDLE;

        # fix the filename

        (undef, undef, $filename) = File::Spec->splitpath($filename);
        $header->{name} = $filename;

        $self->_addFile($header);

        $filecount++;
    }

    return $filecount;
}

sub add_data {
    my $self = shift;
    my ($filename, $data, $params) = @_;

    unless ($filename) {
        $self->_error("No filename given; add_data() can't proceed");
        return;
    }

    $params ||= {};
    $data ||= "";
    
    (undef, undef, $filename) = File::Spec->splitpath($filename);
    
    $params->{name} = $filename;    
    $params->{size} = length($data);
    $params->{data} = $data;
    $params->{uid} ||= 0;
    $params->{gid} ||= 0;
    $params->{date} ||= timelocal(localtime());
    $params->{mode} ||= 0100644;
    
    unless ($self->_addFile($params)) {
        $self->_error("add_data failed due to a failure in _addFile");
        return;
    }

    return $params->{size};     
}

sub write {
    my $self = shift;
    my ($filename) = @_;

    my $outstr;

    $outstr= ARMAG;
    for (@{$self->{_files}}) {
        my $content = $self->get_content($_);
        unless ($content) {
            $self->_error(
                    "Internal Error. $_ file in _files list but no filedata");
            next;
        }

        # For whatever reason, the uids and gids get stripped
        # if they are zero. We'll blank them here to emulate that

        $content->{uid} ||= "";
        $content->{gid} ||= "";
        $outstr.= pack("A16A12A6A6A8A10",
            @$content{qw/name date uid gid/},
            sprintf('%o', $content->{mode}),  # octal!
            $content->{size});
        $outstr.= ARFMAG;
        $outstr.= $content->{data};
        unless (((length($content->{data})) % 2) == 0) {
            # Padding to make up an even number of bytes
            $outstr.= "\n";
        }
    }
    return $outstr unless $filename;

    unless (open HANDLE, ">$filename") {
        $self->_error("Can't open filename $filename");
        return;
    }
    binmode HANDLE;
    print HANDLE $outstr;
    close HANDLE;
    return length($outstr);
}

sub get_content {
    my $self = shift;
    my ($filename) = @_;

    unless ($filename) {
        $self->_error("get_content can't continue without a filename");
        return;
    }

    unless (exists($self->{_filehash}->{$filename})) {
        $self->_error(
                "get_content failed because there is not a file named $filename");
        return;
    }

    return $self->{_filehash}->{$filename};
}

sub DEBUG {
    my $self = shift;
    my $debug = shift;

    $self->{_warn} = 1 unless (defined($debug) and int($debug) == 0);
}

sub error {
    my $self = shift;

    return shift() ? $self->{_longmess} : $self->{_error};
}

sub _parseData {
    my $self = shift;

    unless ($self->{_filedata}) {
        $self->_error("Cannot parse this archive. It appears to be blank");
        return;
    }
    my $scratchdata = $self->{_filedata};

    unless (substr($scratchdata, 0, SARMAG, "") eq ARMAG) {
        $self->_error("Bad magic header token. Either this file is not an ar archive, or it is damaged. If you are sure of the file integrity, Archive::Ar may not support this type of ar archive currently. Please report this as a bug");
        return "";
    }

    while ($scratchdata =~ /\S/) {
        if ($scratchdata =~ s/^(.{58})`\n//s) {
            my $headers = {};
            @$headers{qw/name date uid gid mode size/} =
                unpack("A16A12A6A6A8A10", $1);

            for (values %$headers) {
                $_ =~ s/\s*$//;
            }
            $headers->{mode} = oct($headers->{mode});

            $headers->{data} = substr($scratchdata, 0, $headers->{size}, "");
            # delete padding, if any
            substr($scratchdata, 0, $headers->{size} % 2, "");

            $self->_addFile($headers);
        }
        else {
            $self->_error("File format appears to be corrupt. The file header is not of the right size, or does not exist at all");
            return;
        }
    }

    return scalar($self->{_files});
}

sub _readFromFilename {
    my $self = shift;
    my ($filename) = @_;

    my $handle;
    open $handle, $filename or return;
    binmode $handle;
    return $self->_readFromFilehandle($handle);
}

sub _readFromFilehandle {
    my $self = shift;
    my ($filehandle) = @_;
    return unless $filehandle;

    #handle has to be open
    return unless fileno $filehandle;

    local $/ = undef;
    $self->{_filedata} = <$filehandle>;
    close $filehandle;

    return length($self->{_filedata});
}

sub _addFile {
    my $self = shift;
    my ($file) = @_;

    return unless $file;

    for (qw/name date uid gid mode size data/) {
        unless (exists($file->{$_})) {
            $self->_error(
                    "Can't _addFile because virtual file is missing $_ parameter");
            return;
        }
    }
    
    if (exists($self->{_filehash}->{$file->{name}})) {
        $self->_error("Can't _addFile because virtual file already exists with that name in the archive");
        return;
    }

    push @{$self->{_files}}, $file->{name};
    $self->{_filehash}->{$file->{name}} = $file;

    return $file->{name};
}

sub _remFile {
    my $self = shift;
    my ($filename) = @_;

    return unless $filename;
    if (exists($self->{_filehash}->{$filename})) {
        delete $self->{_filehash}->{$filename};
        @{$self->{_files}} = grep(!/^$filename$/, @{$self->{_files}});
        return 1;
    }
    $self->_error(
        "Can't remove file $filename, because it doesn't exist in the archive");
    return 0;
}

sub _initValues {
    my $self = shift;

    $self->{_files} = [];
    $self->{_filehash} = {};
    $self->{_filedata} ="";

    return;
}

sub _error {
    my $self = shift;
    my $msg = shift;

    $self->{_error} = $msg;
    $self->{_longerror} = longmess($msg);
    if ($self->{_debug}) {
        carp $self->{_error};
    }
}

1;

__END__

=head1 NAME

Archive::Ar - Interface for manipulating ar archives

=head1 SYNOPSIS

    use Archive::Ar;

    my $ar = new Archive::Ar("./foo.ar");

    $ar->add_data("newfile.txt","Some contents", $properties);

    $ar->add_files("./bar.tar.gz", "bat.pl")
    $ar->add_files(["./again.gz"]);

    $ar->remove("file1", "file2");
    $ar->remove(["file1", "file2");

    my $filedata = $ar->get_content("bar.tar.gz");

    my @files = $ar->list_files();
    $ar->read("foo.deb");

    $ar->write("outbound.ar");

    $ar->error();


=head1 DESCRIPTION

Archive::Ar is a pure-perl way to handle standard ar archives.  

This is useful if you have those types of old archives on the system, but it 
is also useful because .deb packages for the Debian GNU/Linux distribution are 
ar archives. This is one building block in a future chain of modules to build, 
manipulate, extract, and test debian modules with no platform or architecture 
dependence.

You may notice that the API to Archive::Ar is similar to Archive::Tar, and
this was done intentionally to keep similarity between the Archive::*
modules


=head2 Class Methods

=over 4

=item * C<new()>

=item * C<new(I<$filename>)>

=item * C<new(I<*GLOB>)>

Returns a new Archive::Ar object.  Without a filename or glob, it returns an
empty object.  If passed a filename as a scalar or in a GLOB, it will attempt
to populate from either of those sources.  If it fails, you will receive 
undef, instead of an object reference. 

=back

=over 4

=item * C<read(I<$filename>)>

=item * C<read(I<*GLOB>)>;

This reads a new file into the object, removing any ar archive already
represented in the object.

=back

=over 4

=item * C<read_memory(I<$data>)>

This read information from the first parameter, and attempts to parse and treat
it like an ar archive. Like C<read()>, it will wipe out whatever you have in the
object and replace it with the contents of the new archive, even if it fails.
Returns the number of bytes read (processed) if successful, undef otherwise.

=back

=over 4

=item * C<list_files()>

This lists the files contained inside of the archive by filename, as an array.
If called in a scalar context, returns a reference to an array.

=back

=over 4

=item * C<add_files(I<"filename1">, I<"filename2">)>

=item * C<add_files(I<["filename1", "filename2"]>)>

Takes an array or an arrayref of filenames to add to the ar archive, in order.
The filenames can be paths to files, in which case the path information is 
stripped off.  Filenames longer than 16 characters are truncated when written
to disk in the format, so keep that in mind when adding files.

Due to the nature of the ar archive format, C<add_files()> will store the uid,
gid, mode, size, and creation date of the file as returned by C<stat()>; 

C<add_files()> returns the number of files successfully added, or undef on failure.

=back

=over 4

=item * C<add_data(I<"filename">, I<$filedata>)>

Takes an filename and a set of data to represent it. Unlike C<add_files>, C<add_data>
is a virtual add, and does not require data on disk to be present. The
data is a hash that looks like:

    $filedata = {
          "data" => $data,
          "uid" => $uid, #defaults to zero
          "gid" => $gid, #defaults to zero
          "date" => $date,  #date in epoch seconds. Defaults to now.
          "mode" => $mode, #defaults to 0100644;
    }

You cannot add_data over another file however.  This returns the file length in 
bytes if it is successful, undef otherwise.

=back

=over 4


=item * C<write()>

=item * C<write(I<"filename.ar">)>

This method will return the data as an .ar archive, or will write to the 
filename present if specified.  If given a filename, C<write()> will return the 
length of the file written, in bytes, or undef on failure.  If the filename
already exists, it will overwrite that file.

=back

=over 4

=item * C<get_content(I<"filename">)>

This returns a hash with the file content in it, including the data that the 
file would naturally contain.  If the file does not exist or no filename is
given, this returns undef. On success, a hash is returned with the following
keys:

    name - The file name
    date - The file date (in epoch seconds)
    uid  - The uid of the file
    gid  - The gid of the file
    mode - The mode permissions
    size - The size (in bytes) of the file
    data - The contained data

=back


=over 4

=item * C<remove(I<"filename1">, I<"filename2">)>

=item * C<remove(I<["filename1", "filename2"]>)>

The remove method takes a filenames as a list or as an arrayref, and removes
them, one at a time, from the Archive::Ar object.  This returns the number
of files successfully removed from the archive.

=back

=over 4

=item * C<error(I<$bool>)>

Returns the current error string, which is usually the last error reported.
If a true value is provided, returns the error message and stack trace.

=back

=head1 CHANGES

=over 4

=item * B<Version 1.15> - May 14, 2013

Use binmode for portability.  Closes RT #81310 (thanks to Stanislav Meduna).

=item * B<Version 1.14> - October 14, 2009

Fix list_files to return a list in list context, to match doc.

Pad odd-size archives to an even number of bytes.
Closes RT #18383 (thanks to David Dick).

Fixed broken file perms (decimal mode stored as octal string).
Closes RT #49987 (thanks to Stephen Gran - debian bug #523515).

=item * B<Version 1.13b> - May 7th, 2003

Fixes to the Makefile.PL file. Ar.pm wasn't being put into /blib
Style fix to a line with non-standard unless parenthesis

=item * B<Version 1.13> - April 30th, 2003

Removed unneeded exports. Thanks to pudge for the pointer.

=item * B<Version 1.12> - April 14th, 2003

Found podchecker. CPAN HTML documentation should work right now.

=item * B<Version 1.11> - April 10th, 2003

Trying to get the HTML POD documentation to come out correctly

=item * B<Version 1.1> - April 10th, 2003

Documentation cleanups
Added a C<remove()> function

=item * B<Version 1.0> - April 7th, 2003

This is the initial public release for CPAN, so everything is new.

=back

=head1 TODO

A better unit test suite perhaps. I have a private one, but a public one would be
nice if there was good file faking module.

Fix / investigate stuff in the BUGS section.

=head1 BUGS

To be honest, I'm not sure of a couple of things. The first is that I know 
of ar archives made on old AIX systems (pre 4.3?) that have a different header
with a different magic string, etc.  This module perfectly (hopefully) handles
ar archives made with the modern ar command from the binutils distribution. If
anyone knows of anyway to produce these old-style AIX archives, or would like
to produce a few for testing, I would be much grateful.

There's no really good reason why this module I<shouldn't> run on Win32 
platforms, but admittedly, this might change when we have a file exporting 
function that supports owner and permission writing.

If you read in and write out a file, you get different md5sums, but it's still
a valid archive. I'm still investigating this, and consider it a minor bug.

=head1 COPYRIGHT

Archive::Ar is copyright 2003 Jay Bonci E<lt>jaybonci@cpan.orgE<gt>. 
This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
