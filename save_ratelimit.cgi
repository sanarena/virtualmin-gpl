#!/usr/bin/perl
# Enable and configure or disable rate limiting

require './virtual-server-lib.pl';
&error_setup($text{'ratelimit_err'});
&can_edit_templates() || &error($text{'ratelimit_ecannot'});
&ReadParse();

# Validate inputs
$in{'max_def'} || &check_ratelimit_field("max", $text{'ratelimit_emax'});
for(my $i=0; defined($did = $in{"dom_$i"}); $i++) {
	next if (!$did);
	$d = &get_domain($did);
	$d || &error($text{'ratelimit_edomid'});
	&check_ratelimit_field("max_$i",
		&text('ratelimit_emaxdom', &show_domain_name($d)));
	}

&ui_print_unbuffered_header(undef, $text{'ratelimit_title'}, "");

if ($in{'enable'} && !&is_ratelimit_enabled()) {
	# Need to enable
	&enable_ratelimit();
	$action = "enable";
	}
elsif (!$in{'enable'} && &is_ratelimit_enabled()) {
	# Need to disable
	&disable_ratelimit();
	$action = "disable";
	}
else {
	$action = "modify";
	}

# Update config
&$first_print($text{'ratelimit_updating'});
&lock_file(&get_ratelimit_config_file());
$conf = &get_ratelimit_config();

# Save global max
&parse_ratelimit_field("max", $conf, "virtualmin_limit", ".*");

# Save per-domain maxes
@rls = grep { $_->{'name'} eq 'ratelimit' &&
              $_->{'values'}->[0] =~ /^"domain_(\d+)"/ } @$conf;
@racls = grep { $_->{'name'} eq 'racl' &&
                $_->{'values'}->[4] =~ /^"domain_(\d+)"/ } @$conf;
for(my $i=0; defined($did = $in{"dom_$i"}); $i++) {
	next if (!$did);
	$d = &get_domain($did);
	&parse_ratelimit_field("max_$i", $conf, "domain_$did",
			       ".*\@$d->{'dom'}");
	$done{$did}++;
	}

# Remove per-domain maxes that are no longer used
foreach my $rl (@rls) {
	if ($rl->{'values'}->[0] =~ /^"domain_(\d+)"/ && !$done{$1}) {
		&save_ratelimit_directive($conf, $rl, undef);
		}
	}
foreach my $racl (@racls) {
	if ($racl->{'values'}->[4] =~ /^"domain_(\d+)"/ && !$done{$1}) {
		&save_ratelimit_directive($conf, $racl, undef);
		}
	}

&flush_file_lines();
&unlock_file(&get_ratelimit_config_file());
&$second_print($text{'setup_done'});

&ui_print_footer("ratelimit.cgi", $text{'ratelimit_return'});

# check_ratelimit_field(name, message)
# Checks the rate-limit field of some name
sub check_ratelimit_field
{
my ($name, $msg) = @_;
$in{$name."_num"} =~ /^\d+$/ || &error($msg." : ".$text{'ratelimit_enum'});
$in{$name."_time"} =~ /^\d+$/ || &error($msg." : ".$text{'ratelimit_etime'});
}

# parse_ratelimit_field(name, &config, config-limit-name, regexp)
# Update the ratelimit of some type
sub parse_ratelimit_field
{
my ($name, $conf, $ratelimit, $regexp) = @_;

# Get existing limit objects
my ($rl) = grep { $_->{'name'} eq 'ratelimit' &&
	          $_->{'values'}->[0] eq "\"$ratelimit\"" } @$conf;
my ($racl) = grep { $_->{'name'} eq 'racl' &&
		    $_->{'values'}->[0] eq 'blacklist' &&
		    $_->{'values'}->[3] eq 'ratelimit' &&
	            $_->{'values'}->[4] eq "\"$ratelimit\"" } @$conf;
my ($defracl) = grep { $_->{'name'} eq 'racl' &&
		       $_->{'values'}->[0] eq 'whitelist' &&
		       $_->{'values'}->[1] eq 'default' } @$conf;
if ($in{$name."_def"}) {
	# Remove existing lines
	&save_ratelimit_directive($conf, $rl, undef);
	&save_ratelimit_directive($conf, $racl, undef);
	}
else {
	# Add or update
	my $newrl = { 'name' => 'ratelimit',
		      'values' => [
			"\"$ratelimit\"", 'rcpt', $in{$name."_num"},
			"/", $in{$name."_time"}.$in{$name."_units"} ],
		    };
	my $newracl = { 'name' => 'racl',
			'values' => [
			  'blacklist', 'from', "/$regexp/", 'ratelimit',
			  "\"$ratelimit\"",
			  'msg', '"Message quota exceeded"' ],
		      };
	&save_ratelimit_directive($conf, $rl, $newrl, $defracl);
	&save_ratelimit_directive($conf, $racl, $newracl, $defracl);
	}
}