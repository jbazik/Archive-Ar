use ExtUtils::MakeMaker;

WriteMakefile(
	'NAME'		=> 'Archive::Ar',
	'VERSION_FROM'	=> 'lib/Archive/Ar.pm', # finds $VERSION
	'PREREQ_PM'	=>
		{ 
			'Test::More' => '0.45',
			'File::Spec' => '0.83',
			'Time::Local' => '1.04',
			'Test::MockObject' => '0.12',
		},

	'dist'		=> 
		{
			COMPRESS => 'gzip -9',
			SUFFIX   => '.gz',
			DIST_DEFAULT => 'all tardist',
		},

	($] >= 5.005 ?    ## Add these new keywords supported since 5.005
		(
			ABSTRACT_FROM	=> 'lib/Archive/Ar.pm', # retrieve abstract from module
			AUTHOR     	=> 'Jay Bonci <jay@bonci.com>') 
		: ()),
);

