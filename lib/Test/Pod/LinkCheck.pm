#
# This file is part of Test-Pod-LinkCheck
#
# This software is copyright (c) 2011 by Apocalypse.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
use strict; use warnings;
package Test::Pod::LinkCheck;
BEGIN {
  $Test::Pod::LinkCheck::VERSION = '0.007';
}
BEGIN {
  $Test::Pod::LinkCheck::AUTHORITY = 'cpan:APOCAL';
}

# ABSTRACT: Tests POD for invalid links

# Import the modules we need
use Moose 1.01;
use Test::Pod 1.44 ();
use App::PodLinkCheck::ParseLinks 4;

# setup our tests and etc
use Test::Builder 0.94;
my $Test = Test::Builder->new;

# export our 2 subs
use parent qw( Exporter );
our @EXPORT_OK = qw( pod_ok all_pod_ok );


has 'check_cpan' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 1,
);

{
	use Moose::Util::TypeConstraints 1.01;


	# TODO add CPANIDX?
	has 'cpan_backend' => (
		is	=> 'rw',
		isa	=> enum( [ qw( CPANPLUS CPAN CPANSQLite ) ] ),
		default	=> 'CPANPLUS',
		trigger => \&_clean_cpan_backend,
	);

	sub _clean_cpan_backend {
		my( $self, $new, $old ) = @_;

		# Just clear the cpan cache
		$self->_cache->{'cpan'} = {};
		$self->_backend_err( 0 );
	}
}


has 'cpan_backend_auto' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 1,
);


has 'cpan_section_err' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);


has 'verbose' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

# holds the cached results of link look-ups
has '_cache' => (
	is	=> 'ro',
	isa	=> 'HashRef',
	default	=> sub { return {
		'cpan'		=> {},
		'man'		=> {},
		'pod'		=> {},
		'section'	=> {},
	} },
);

# is the backend good to use?
has '_backend_err' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
	trigger => \&_clean_backend_err,
);

sub _clean_backend_err {
	my( $self, $new, $old ) = @_;

	# Only clean if an error happened
	if ( $new ) {
		$self->_cache->{'cpan'} = {};
	}
}


sub pod_ok {
	my $self = shift;
	my $file = shift;

	if ( ! ref $self ) {	# Allow function call
		$file = $self;
		$self = __PACKAGE__->new;
	}

	my $name = @_ ? shift : "LinkCheck test for $file";

	if ( ! -f $file ) {
		$Test->ok( 0, $name );

		if ( $self->verbose ) {
			$Test->diag( "Extra: " );
			$Test->diag( " * '$file' does not exist?" );
		}

		return 0;
	}

	# Parse the POD!
	my $parser = App::PodLinkCheck::ParseLinks->new( {} );
	my $output;

	# Override some options that the podlinkcheck subclass "helpfully" set for us...
	$parser->output_string( \$output );
	$parser->complain_stderr( 0 );
	$parser->no_errata_section( 0 );
	$parser->no_whining( 0 );
	$parser->parse_file( $file );

	# is POD well-formed?
	if ( $parser->any_errata_seen ) {
		$Test->ok( 0, $name );

		if ( $self->verbose ) {
			$Test->diag( "Extra: " );
			$Test->diag( " * Unable to parse POD in '$file'" );

			# TODO ugly, but there is no other way to get at it?
			## no critic ( ProhibitAccessOfPrivateData )
			foreach my $l ( keys %{ $parser->{'errata'} } ) {
				$Test->diag( " * errors seen in line $l:" );
				$Test->diag( "   * $_" ) for @{ $parser->{'errata'}{$l} };
			}
		}

		return 0;
	}

	# Did we see POD in the file?
	if ( $parser->doc_has_started ) {
		my( $err, $diag ) = $self->_analyze( $parser );

		if ( scalar @$err > 0 ) {
			$Test->ok( 0, $name );
			$Test->diag( "Erroneous links: " );
			$Test->diag( " * $_" ) for @$err;

			if ( $self->verbose and @$diag ) {
				$Test->diag( "Extra: " );
				$Test->diag( " * $_" ) for @$diag;
			}

			return 0;
		} else {
			$Test->ok( 1, $name );

			if ( $self->verbose and @$diag ) {
				$Test->diag( "Extra: " );
				$Test->diag( " * $_" ) for @$diag;
			}
		}
	} else {
		$Test->ok( 1, $name );

		if ( $self->verbose ) {
			$Test->diag( "Extra: " );
			$Test->diag( " * There is no POD in '$file' ?" );
		}
	}

	return 1;
}


sub all_pod_ok {
	my $self = shift;
	my @files = @_ ? @_ : Test::Pod::all_pod_files();

	if ( ! defined $self or ! ref $self ) {	# Allow function call
		unshift( @files, $self ) if defined $self;
		$self = __PACKAGE__->new;
	}

	$Test->plan( tests => scalar @files );

	my $ok = 1;
	foreach my $file ( @files ) {
		$self->pod_ok( $file ) or undef $ok;
	}

	return $ok;
}

sub _analyze {
	my( $self, $parser ) = @_;

	my $file = $parser->source_filename;
	my $links = $parser->links_arrayref;
	my $own_sections = $parser->sections_hashref;
	my( @errors, @diag );

	foreach my $l ( @$links ) {
		## no critic ( ProhibitAccessOfPrivateData )
		my( $type, $to, $section, $linenum, $column ) = @$l;
		push( @diag, "$file:$linenum:$column - Checking link type($type) to(" . ( defined $to ? $to : '' ) . ") " .
			"section(" . ( defined $section ? $section : '' ) . ")" ) if $self->verbose;

		# What kind of link?
		if ( $type eq 'man' ) {
			if ( ! $self->_known_manpage( $to ) ) {
				push( @errors, "$file:$linenum:$column - Unknown link type(man) to($to)" );
			}
		} elsif ( $type eq 'pod' ) {
			# do we have a to/section?
			if ( defined $to ) {
				if ( defined $section ) {
					# Do we have this file installed?
					if ( ! $self->_known_podlink( $to, $section ) ) {
						# Is it a CPAN module?
						my $res = $self->_known_cpan( $to );
						if ( defined $res ) {
							if ( $res ) {
								# if true, treat cpan sections as errors because we can't verify if section exists
								if ( $self->cpan_section_err ) {
									push( @errors, "$file:$linenum:$column - Unable to verify link type(pod) to($to) section($section) because the module isn't installed" );
								} else {
									push( @diag, "$file:$linenum:$column - Unable to verify link type(pod) to($to) section($section) because the module isn't installed" );
								}
							} else {
								push( @errors, "$file:$linenum:$column - Unknown link type(pod) to($to) section($section) - module doesn't exist in CPAN" );
							}
						} else {
							push( @errors, "$file:$linenum:$column - Unknown link type(pod) to($to) section($section) - unable to check CPAN" );
						}
					}
				} else {
					# Is it a perlfunc reference?
					if ( ! $self->_known_perlfunc( $to ) ) {
						# Do we have this file installed?
						if ( ! $self->_known_podfile( $to ) ) {
							# Sometimes we find a manpage but not the pod...
							if ( ! $self->_known_manpage( $to ) ) {
								# Is it a CPAN module?
								my $res = $self->_known_cpan( $to );
								if ( defined $res ) {
									if ( ! $res ) {
										# Check for internal section
										if ( exists $own_sections->{ $to } ) {
											push( @diag, "$file:$linenum:$column - Link type(pod) to($to) looks like an internal section link - recommend 'L</$to>'" );
										} else {
											push( @errors, "$file:$linenum:$column - Unknown link type(pod) to($to) - module doesn't exist in CPAN" );
										}
									}
								} else {
									# Check for internal section
									if ( exists $own_sections->{ $to } ) {
										push( @diag, "$file:$linenum:$column - Link type(pod) to($to) looks like an internal section link - recommend 'L</$to>'" );
									} else {
										push( @errors, "$file:$linenum:$column - Unknown link type(pod) to($to) - unable to check CPAN" );
									}
								}
							}
						}
					}
				}
			} else {
				if ( defined $section ) {
					if ( ! exists $own_sections->{ $section } ) {
						push( @errors, "$file:$linenum:$column - Unknown link type(pod) to() section($section) - section doesn't exist!" );
					}
				} else {
					# no to/section eh?
					push( @errors, "$file:$linenum:$column - Malformed link type(pod) to() section()" );
				}
			}
		} else {
			# unknown type?
			push( @errors, "$file:$linenum:$column - Unknown link type($type) to(" . ( defined $to ? $to : '' ) . ") section(" . ( defined $section ? $section : '' ) . ")" );
		}
	}

	return( \@errors, \@diag );
}

sub _known_perlfunc {
	my( $self, $func ) = @_;
	my $cache = $self->_cache->{'func'};

	if ( ! exists $cache->{ $func } ) {
		# TODO this sucks, but Pod::Perldoc can't do it because it expects to be ran in the console...
		require Capture::Tiny;
		$cache->{ $func } = Capture::Tiny::capture_merged( sub {
			system( 'perldoc -f ' . $func );
		} );

		# We need at least 5 newlines to guarantee a real perlfunc
		# apoc@blackhole:~$ perldoc -f foobar
		# No documentation for perl function `foobar' found
		if ( ( $cache->{ $func } =~ tr/\n// ) > 5 ) {
			$cache->{ $func } = 1;
		} else {
			$cache->{ $func } = 0;
		}
	}

	return $cache->{ $func };
}

sub _known_manpage {
	my( $self, $page ) = @_;
	my $cache = $self->_cache->{'man'};

	if ( ! exists $cache->{ $page } ) {
		my @manargs;
		if ( $page =~ /(.+)\s*\((.+)\)$/ ) {
			@manargs = ($2, $1);
		} else {
			@manargs = ($page);
		}

		require Capture::Tiny;
		$cache->{ $page } = Capture::Tiny::capture_merged( sub {
			system( 'man', @manargs );
		} );

		# We need at least 5 newlines to guarantee a real manpage
		if ( ( $cache->{ $page } =~ tr/\n// ) > 5 ) {
			$cache->{ $page } = 1;
		} else {
			$cache->{ $page } = 0;
		}
	}

	return $cache->{ $page };
}

sub _known_podfile {
	my( $self, $link ) = @_;
	my $cache = $self->_cache->{'pod'};

	if ( ! exists $cache->{ $link } ) {
		# Is it a plain POD file?
		require Pod::Find;
		my $filename = Pod::Find::pod_where( {
			'-inc'	=> 1,
		}, $link );
		if ( defined $filename ) {
			$cache->{ $link } = $filename;
		} else {
			# It might be a script...
			require File::Spec;
			require Config;
			foreach my $dir ( split /\Q$Config::Config{'path_sep'}/o, $ENV{'PATH'} ) {
				$filename = File::Spec->catfile( $dir, $link );
				if ( -e $filename ) {
					$cache->{ $link } = $filename;
					last;
				}
			}
			if ( ! exists $cache->{ $link } ) {
				$cache->{ $link } = 0;
			}
		}
	}

	return $cache->{ $link };
}

sub _known_cpan {
	my( $self, $module ) = @_;

	# Do we even check CPAN?
	if ( ! $self->check_cpan ) {
		return;
	}

	# Did the backend encounter an error?
	if ( $self->_backend_err ) {
		return;
	}

	# Sanity check - we use '.' as the actual cache placeholder...
	if ( $module eq '.' ) {
		return;
	}

	# is the answer cached already?
	if ( exists $self->_cache->{'cpan'}{ $module } ) {
		return $self->_cache->{'cpan'}{ $module };
	}

	# Select the backend?
	if ( $self->cpan_backend eq 'CPANPLUS' ) {
		return $self->_known_cpan_cpanplus( $module );
	} elsif ( $self->cpan_backend eq 'CPAN' ) {
		return $self->_known_cpan_cpan( $module );
	} elsif ( $self->cpan_backend eq 'CPANSQLite' ) {
		return $self->_known_cpan_cpansqlite( $module );
	} else {
		die "Unknown backend: " . $self->cpan_backend;
	}
}

sub _known_cpan_cpanplus {
	my( $self, $module ) = @_;
	my $cache = $self->_cache->{'cpan'};

	# init the backend ( and set some options )
	if ( ! exists $cache->{'.'} ) {
		eval {
			# Wacky format so dzil will not autoprereq it
			require 'CPANPLUS/Backend.pm'; require 'CPANPLUS/Configure.pm';

			my $cpanconfig = CPANPLUS::Configure->new;
			$cpanconfig->set_conf( 'verbose' => 0 );
			$cpanconfig->set_conf( 'no_update' => 1 );

			# ARGH, CPANIDX doesn't work well with this kind of search...
			# TODO check if it's still true?
			if ( $cpanconfig->get_conf( 'source_engine' ) =~ /CPANIDX/ ) {
				$cpanconfig->set_conf( 'source_engine' => 'CPANPLUS::Internals::Source::Memory' );
			}

			# silence CPANPLUS!
			eval "no warnings 'redefine'; sub Log::Message::store { return }";
			local $SIG{'__WARN__'} = sub { return };
			$cache->{'.'} = CPANPLUS::Backend->new( $cpanconfig );
		};
		if ( $@ ) {
			warn "Unable to load CPANPLUS - $@" if $self->verbose;
			if ( $self->cpan_backend_auto ) {
				$self->cpan_backend( 'CPAN' );
				return $self->_known_cpan_cpan( $module );
			} else {
				$self->_backend_err( 1 );
				return;
			}
		}
	}

	my $result;
	eval { local $SIG{'__WARN__'} = sub { return }; $result = $cache->{'.'}->parse_module( 'module' => $module ) };
	if ( $@ ) {
		warn "Unable to use CPANPLUS - $@" if $self->verbose;
		if ( $self->cpan_backend_auto ) {
			$self->cpan_backend( 'CPAN' );
			return $self->_known_cpan_cpan( $module );
		} else {
			$self->_backend_err( 1 );
			return;
		}
	}
	if ( defined $result ) {
		$cache->{ $module } = 1;
	} else {
		$cache->{ $module } = 0;
	}

	return $cache->{ $module };
}

sub _known_cpan_cpan {
	my( $self, $module ) = @_;
	my $cache = $self->_cache->{'cpan'};

	# init the backend ( and set some options )
	if ( ! exists $cache->{'.'} ) {
		eval {
			# Wacky format so dzil will not autoprereq it
			require 'CPAN.pm';

			# TODO this code stolen from App::PodLinkCheck
			# not sure how far back this will work, maybe only 5.8.0 up
			if ( ! $CPAN::Config_loaded && CPAN::HandleConfig->can( 'load' ) ) {
				# fake $loading to avoid running the CPAN::FirstTime dialog -- is this the right way to do that?
				local $CPAN::HandleConfig::loading = 1;
				CPAN::HandleConfig->load;
			}

			# figure out the access method
			if ( defined $CPAN::META && %$CPAN::META ) {
	 			# works already!
			} elsif ( ! CPAN::Index->can('read_metadata_cache') ) {
				# Argh, we can't use it...
				die "Unable to use CPAN.pm metadata cache!";
			} else {
				# try the .cpan/Metadata even if CPAN::SQLite is installed, just in
				# case the SQLite is not up-to-date or has not been used yet
				local $CPAN::Config->{use_sqlite} = $CPAN::Config->{use_sqlite} = 0;	# stupid used once warning...
				CPAN::Index->read_metadata_cache;
				if ( defined $CPAN::META && %$CPAN::META ) {
					# yay, works!
				} else {
					die "Unable to use CPAN.pm metadata cache!";
				}
			}

			# Cache is ready
			$cache->{'.'} = $CPAN::META->{'readwrite'}->{'CPAN::Module'};
		};
		if ( $@ ) {
			warn "Unable to load CPAN - $@" if $self->verbose;
			if ( $self->cpan_backend_auto ) {
				$self->cpan_backend( 'CPANSQLite' );
				return $self->_known_cpan_cpansqlite( $module );
			} else {
				$self->_backend_err( 1 );
				return;
			}
		}
	}

	if ( exists $cache->{'.'}{ $module } ) {
		$cache->{ $module } = 1;
	} else {
		$cache->{ $module } = 0;
	}

	return $cache->{ $module };
}

sub _known_cpan_cpansqlite {
	my( $self, $module ) = @_;
	my $cache = $self->_cache->{'cpan'};

	# init the backend ( and set some options )
	if ( ! exists $cache->{'.'} ) {
		eval {
			# Wacky format so dzil will not autoprereq it
			require 'CPAN.pm'; require 'CPAN/SQLite.pm';

			# TODO this code stolen from App::PodLinkCheck
			# not sure how far back this will work, maybe only 5.8.0 up
			if ( ! $CPAN::Config_loaded && CPAN::HandleConfig->can( 'load' ) ) {
				# fake $loading to avoid running the CPAN::FirstTime dialog -- is this the right way to do that?
				local $CPAN::HandleConfig::loading = 1;
				CPAN::HandleConfig->load;
			}

			$cache->{'.'} = CPAN::SQLite->new;
		};
		if ( $@ ) {
			warn "Unable to load CPANSQLite - $@" if $self->verbose;
			if ( $self->cpan_backend_auto ) {
				warn "Unable to use any CPAN backend, disabling searches!" if $self->verbose;
				$self->check_cpan( 0 );
				$self->cpan_section_err( 1 );
			}

			$self->_backend_err( 1 );
			return;
		}
	}

	my $result;
	eval { local $SIG{'__WARN__'} = sub { return }; $result = $cache->{'.'}->query( 'mode' => 'module', name => $module, max_results => 1 ); };
	if ( $@ ) {
		warn "Unable to use CPANSQLite - $@" if $self->verbose;
		if ( $self->cpan_backend_auto ) {
			warn "Unable to use any CPAN backend, disabling searches!" if $self->verbose;
			$self->check_cpan( 0 );
			$self->cpan_section_err( 1 );
		}

		$self->_backend_err( 1 );
		return;
	}
	if ( $result ) {
		$cache->{ $module } = 1;
	} else {
		$cache->{ $module } = 0;
	}

	return $cache->{ $module };
}

sub _known_podlink {
	my( $self, $link, $section ) = @_;

	# First of all, does the file exists?
	my $filename = $self->_known_podfile( $link );
	return 0 if ! defined $filename;

	# Okay, get the sections in the file and see if the link matches
	my $file_sections = $self->_known_podsections( $filename );
	if ( defined $file_sections and exists $file_sections->{ $section } ) {
		return 1;
	} else {
		return 0;
	}
}

sub _known_podsections {
	my( $self, $filename ) = @_;
	my $cache = $self->_cache->{'sections'};

	if ( ! exists $cache->{ $filename } ) {
		# Okay, get the sections in the file
		require App::PodLinkCheck::ParseSections;
		my $parser = App::PodLinkCheck::ParseSections->new( {} );
		$parser->parse_file( $filename );
		$cache->{ $filename } = $parser->sections_hashref;
	}

	return $cache->{ $filename };
}

# from Moose::Manual::BestPractices
no Moose;
__PACKAGE__->meta->make_immutable;

1;


__END__
=pod

=for :stopwords Apocalypse cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee
diff irc mailto metadata placeholders CPAN foo OO backend env CPANPLUS
CPANSQLite http

=encoding utf-8

=head1 NAME

Test::Pod::LinkCheck - Tests POD for invalid links

=head1 VERSION

  This document describes v0.007 of Test::Pod::LinkCheck - released April 21, 2011 as part of Test-Pod-LinkCheck.

=head1 SYNOPSIS

	#!/usr/bin/perl
	use strict; use warnings;

	use Test::More;

	eval "use Test::Pod::LinkCheck";
	if ( $@ ) {
		plan skip_all => 'Test::Pod::LinkCheck required for testing POD';
	} else {
		Test::Pod::LinkCheck->new->all_pod_ok;
	}

=head1 DESCRIPTION

This module looks for any links in your POD and verifies that they point to a valid resource. It uses the L<Pod::Simple> parser
to analyze the pod files and look at their links. In a nutshell, it looks for C<LE<lt>FooE<gt>> links and makes sure that Foo
exists. It also recognizes section links, C<LE<lt>/SYNOPSISE<gt>> for example. Also, manpages are resolved and checked.

This module does B<NOT> check "http" links like C<LE<lt>http://www.google.comE<gt>> in your pod. For that, please check
out L<Test::Pod::No404s>.

Normally, you wouldn't want this test to be run during end-user installation because they might not have the modules installed! It is
HIGHLY recommended that this be used only for module authors' RELEASE_TESTING phase. To do that, just modify the synopsis to
add an env check :)

This module normally uses the OO method to run tests, but you can use the functional style too. Just explicitly ask for the C<all_pod_ok> or
C<pod_ok> function to be imported when you use this module.

	#!/usr/bin/perl
	use strict; use warnings;
	use Test::Pod::LinkCheck qw( all_pod_ok );
	all_pod_ok();

=head1 ATTRIBUTES

=head2 check_cpan

If enabled, this module will check the CPAN module database to see if a link is a valid CPAN module or not. It uses the backend
defined in L</cpan_backend> to do the actual searching.

If disabled, it will resolve links based on locally installed modules. If it isn't installed it will be an error!

The default is: true

=head2 cpan_backend

Selects the CPAN backend to use for querying modules. The available ones are: CPANPLUS, CPAN, and CPANSQLite.

The default is: CPANPLUS

	The backends were tested and verified against those versions. Older versions should work, but is untested!
		CPANPLUS v0.9010
		CPAN v1.9402
		CPAN::SQLite v0.199

=head2 cpan_backend_auto

Enable to automatically try the CPAN backends to find an available one. It will try the backends in the order defined in L</cpan_backend>

If no backend is available, it will disable the L</check_cpan> attribute and enable the L</cpan_section_err> attribute.

The default is: true

=head2 cpan_section_err

If enabled, a link pointing to a CPAN module's specific section is treated as an error if it isn't installed.

The default is: false

=head2 verbose

If enabled, this module will print extra diagnostics for the links it's checking.

The default is: false

=head1 METHODS

=head2 pod_ok

Accepts the filename to check, and an optional test name.

This method will pass the test if there is no POD links present in the POD or if all links are not an error. Furthermore, if the POD was
malformed as reported by L<Pod::Simple>, the test will fail and not attempt to check the links.

When it fails, this will show any failing links as diagnostics. Also, some extra information is printed if verbose is enabled.

The default test name is: "LinkCheck test for FILENAME"

=head2 all_pod_ok

Accepts an optional array of files to check. By default it uses all POD files in your distribution.

This method is what you will usually run. Every file is passed to the L</pod_ok> function. This also sets the
test plan to be the number of files.

=head1 NOTES

=head2 backend

This module uses the L<CPANPLUS> and L<CPAN> modules as the backend to verify valid CPAN modules. Please make sure that the backend you
choose is properly configured before running this! This means the index is updated, permissions is set, and whatever else the backend
needs to properly function. If you don't want to use them please disable the L</check_cpan> attribute.

If this module fails to check CPAN modules or the testsuite fails, it's probably because of the above reason.

=head2 CPAN module sections

One limitation of this module is that it can't check for valid sections on CPAN modules if they aren't installed. If you want that to be an
error, please enable the L</cpan_section_err> attribute.

=head1 SEE ALSO

Please see those modules/websites for more information related to this module.

=over 4

=item *

L<App::PodLinkCheck|App::PodLinkCheck>

=item *

L<Pod::Checker|Pod::Checker>

=item *

L<Test::Pod::No404s|Test::Pod::No404s>

=back

=head1 SUPPORT

=head2 Perldoc

You can find documentation for this module with the perldoc command.

  perldoc Test::Pod::LinkCheck

=head2 Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

=over 4

=item *

Search CPAN

The default CPAN search engine, useful to view POD in HTML format.

L<http://search.cpan.org/dist/Test-Pod-LinkCheck>

=item *

RT: CPAN's Bug Tracker

The RT ( Request Tracker ) website is the default bug/issue tracking system for CPAN.

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Test-Pod-LinkCheck>

=item *

AnnoCPAN

The AnnoCPAN is a website that allows community annonations of Perl module documentation.

L<http://annocpan.org/dist/Test-Pod-LinkCheck>

=item *

CPAN Ratings

The CPAN Ratings is a website that allows community ratings and reviews of Perl modules.

L<http://cpanratings.perl.org/d/Test-Pod-LinkCheck>

=item *

CPAN Forum

The CPAN Forum is a web forum for discussing Perl modules.

L<http://cpanforum.com/dist/Test-Pod-LinkCheck>

=item *

CPANTS

The CPANTS is a website that analyzes the Kwalitee ( code metrics ) of a distribution.

L<http://cpants.perl.org/dist/overview/Test-Pod-LinkCheck>

=item *

CPAN Testers

The CPAN Testers is a network of smokers who run automated tests on uploaded CPAN distributions.

L<http://www.cpantesters.org/distro/T/Test-Pod-LinkCheck>

=item *

CPAN Testers Matrix

The CPAN Testers Matrix is a website that provides a visual way to determine what Perls/platforms PASSed for a distribution.

L<http://matrix.cpantesters.org/?dist=Test-Pod-LinkCheck>

=item *

CPAN Testers Dependencies

The CPAN Testers Dependencies is a website that shows a chart of the test results of all dependencies for a distribution.

L<http://deps.cpantesters.org/?module=Test::Pod::LinkCheck>

=back

=head2 Email

You can email the author of this module at C<APOCAL at cpan.org> asking for help with any problems you have.

=head2 Internet Relay Chat

You can get live help by using IRC ( Internet Relay Chat ). If you don't know what IRC is,
please read this excellent guide: L<http://en.wikipedia.org/wiki/Internet_Relay_Chat>. Please
be courteous and patient when talking to us, as we might be busy or sleeping! You can join
those networks/channels and get help:

=over 4

=item *

irc.perl.org

You can connect to the server at 'irc.perl.org' and join this channel: #perl-help then talk to this person for help: Apocalypse.

=item *

irc.freenode.net

You can connect to the server at 'irc.freenode.net' and join this channel: #perl then talk to this person for help: Apocal.

=item *

irc.efnet.org

You can connect to the server at 'irc.efnet.org' and join this channel: #perl then talk to this person for help: Ap0cal.

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests by email to C<bug-test-pod-linkcheck at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test-Pod-LinkCheck>. You will be automatically notified of any
progress on the request by the system.

=head2 Source Code

The code is open to the world, and available for you to hack on. Please feel free to browse it and play
with it, or whatever. If you want to contribute patches, please send me a diff or prod me to pull
from your repository :)

L<http://github.com/apocalypse/perl-test-pod-linkcheck>

  git clone git://github.com/apocalypse/perl-test-pod-linkcheck.git

=head1 AUTHOR

Apocalypse <APOCAL@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Apocalypse.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the LICENSE file included with this distribution.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT
WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER
PARTIES PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND,
EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE
SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME
THE COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE LIABLE
TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE
SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
DAMAGES.

=cut
