#!/usr/local/bin/perl

=head1 create-domain.pl

Create a virtual server

This program can be used to create a new top-level, child or alias virtual
server. It is typically called with parameters something like :

   create-domain.pl --domain foo.com --pass smeg --desc "The server for foo" --unix --dir --webmin --web --dns --mail --limits-from-plan

This would create a server called foo.com , with the Unix login, home directory, Webmin login, website, DNS domain and email features enabled, and disk quotas
based on those set in the default plan. If you run this program with the --help option, you can see all of the
other command-line options that it supports. The most commonly used are those
for enabling features for the new server, such as --mysql and --logrotate.

To create a virtual server with a private IP address, you can use the --ip
option to specify it explicitly. If your Virtualmin is configured to
automatically allocate IP addresses, use the --allocate-ip option instead, to
have a free address chosen from the allocation ranges. If you want to
use a virtual IP that is already active on the system, you must add the
--ip-already command-line option.

To create a server that is owned by an existing user, use the --parent option,
followed by the name of the virtual server to create under. In this case, the --pass , --unix , --webmin and --quota options are not needed, as a user for the new server already exists.

To create an alias of an existing virtual server, use the --alias option,
followed by the domain name of the target server. For alias servers, the
--pass , --unix , --webmin , --dir and --quota options are not needed.

You can specify limits on the number of aliases, sub-servers, mailboxes and
databases for the new domain owner using the --max-aliases, --max-doms,
--max-mailboxes and --max-dbs options. Alternately, you can choose to have
all limits (including quotas) set based on the plan using the
--limits-from-plan command line flag.

If the virtual server has the MySQL or PostgreSQL features enabled, by default
the password for the server's accounts will be the same as its administration
login. However, you can specify a different password with the --mysql-pass or
--postgres-pass flags, each of which are followed by the password to set for
that database type. These options are only available for top-level virtual
servers though.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/create-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Build args used by plugins
%plugin_args = ( );
foreach $f (@feature_plugins) {
	if (&plugin_defined($f, "feature_args")) {
		foreach $a (&plugin_call($f, "feature_args")) {
			$a->{'feature'} = $f;
			$plugin_args{$a->{'name'}} = $a;
			}
		}
	}

# Parse command-line args
$name = 1;
$virt = 0;
$anylimits = 0;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--desc") {
		$owner = shift(@ARGV);
		$owner =~ /:/ && &usage($text{'setup_eowner'});
		}
	elsif ($a eq "--email") {
		$email = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$user = lc(shift(@ARGV));
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--mysql-pass") {
		$mysqlpass = shift(@ARGV);
		}
	elsif ($a eq "--postgres-pass") {
		$postgrespass = shift(@ARGV);
		}
	elsif ($a eq "--quota") {
		$quota = shift(@ARGV);
		$quota = 0 if ($quota eq "UNLIMITED");
		$anylimits = 1;
		}
	elsif ($a eq "--uquota") {
		$uquota = shift(@ARGV);
		$uquota = 0 if ($uquota eq "UNLIMITED");
		$anylimits = 1;
		}
	elsif ($a =~ /^--(\S+)$/ &&
	       &indexof($1, @features) >= 0) {
		$config{$1} || &usage("The $a option cannot be used unless the feature is enabled in the module configuration");
		$feature{$1}++;
		}
	elsif ($a =~ /^--(\S+)$/ &&
	       &indexof($1, @feature_plugins) >= 0) {
		$plugin{$1}++;
		}
	elsif ($a eq "--default-features") {
		$deffeatures = 1;
		}
	elsif ($a eq "--features-from-template" ||
	       $a eq "--features-from-plan") {
		$planfeatures = 1;
		}
	elsif ($a eq "--ip") {
		$ip = shift(@ARGV);
		if (!$config{'all_namevirtual'}) {
			$feature{'virt'} = 1;	# for dependency checks
			$virt = 1;
			}
		else {
			$virtalready = 1;
			}
		$name = 0;
		}
	elsif ($a eq "--allocate-ip") {
		$ip = "allocate";	# will be done later
		$virt = 1;
		$name = 0;
		}
	elsif ($a eq "--ip-already") {
		$virtalready = 1;
		}
	elsif ($a eq "--ip-primary") {
		&usage("The --ip-primary flag is no longer needed, as a single SSL website can be created for each shared IP address");
		}
	elsif ($a eq "--shared-ip") {
		$sharedip = shift(@ARGV);
		$virt = 0;
		$name = 1;
		&indexof($sharedip, &list_shared_ips()) >= 0 ||
		    &usage("$sharedip is not in the shared IP addresses list");
		}
	elsif ($a eq "--dns-ip") {
		$dns_ip = shift(@ARGV);
		&check_ipaddress($dns_ip) ||
			&usage("--dns-ip must be followed by an IP address");
		}
	elsif ($a eq "--no-dns-ip") {
		$dns_ip = "";
		}
	elsif ($a eq "--mailboxlimit" || $a eq "--max-mailboxes") {
		$mailboxlimit = shift(@ARGV);
		$anylimits = 1;
		}
	elsif ($a eq "--dbslimit" || $a eq "--max-dbs") {
		$dbslimit = shift(@ARGV);
		$anylimits = 1;
		}
	elsif ($a eq "--domslimit" || $a eq "--max-doms") {
		$domslimit = shift(@ARGV);
		$anylimits = 1;
		}
	elsif ($a eq "--aliaslimit" || $a eq "--max-aliases") {
		$aliaslimit = shift(@ARGV);
		$anylimits = 1;
		}
	elsif ($a eq "--aliasdomslimit" || $a eq "--max-aliasdoms") {
		$aliasdomslimit = shift(@ARGV);
		$anylimits = 1;
		}
	elsif ($a eq "--realdomslimit" || $a eq "--max-realdoms") {
		$realdomslimit = shift(@ARGV);
		$anylimits = 1;
		}
	elsif ($a eq "--template") {
		$templatename = shift(@ARGV);
		foreach $t (&list_templates()) {
			if ($t->{'name'} eq $templatename ||
			    $t->{'id'} eq $templatename) {
				$template = $t->{'id'};
				}
			}
		$template eq "" && &usage("Unknown template name");
		}
	elsif ($a eq "--plan") {
		$planname = shift(@ARGV);
		foreach $p (&list_plans()) {
			if ($p->{'id'} eq $planname ||
			    $p->{'name'} eq $planname) {
				$planid = $p->{'id'};
				}
			}
		$planid eq "" && &usage("Unknown plan name");
		}
	elsif ($a eq "--bandwidth") {
		$bw = shift(@ARGV);
		$anylimits = 1;
		}
	elsif ($a eq "--limits-from-template" ||
	       $a eq "--limits-from-plan") {
		$tlimit = 1;
		}
	elsif ($a eq "--prefix") {
		$prefix = shift(@ARGV);
		}
	elsif ($a eq "--db") {
		$db = shift(@ARGV);
		$db =~ /^[a-z0-9\-\_]+$/i || &usage("Invalid database name");
		}
	elsif ($a eq "--fwdto") {
		$fwdto = shift(@ARGV);
		$fwdto =~ /^\S+\@\S+$/i || &usage("Invalid forwarding address");
		}
	elsif ($a eq "--parent") {
		$parentdomain = lc(shift(@ARGV));
		}
	elsif ($a eq "--alias") {
		$aliasdomain = $parentdomain = lc(shift(@ARGV));
		}
	elsif ($a eq "--subdom" || $a eq "--superdom") {
		$subdomain = $parentdomain = lc(shift(@ARGV));
		}
	elsif ($a eq "--reseller") {
		$resel = shift(@ARGV);
		}
	elsif ($a eq "--style") {
		$stylename = shift(@ARGV);
		}
	elsif ($a eq "--content") {
		$content = shift(@ARGV);
		}
	elsif ($a eq "--no-email") {
		$nocreationmail = 1;
		}
	elsif ($a eq "--no-slaves") {
		$noslaves = 1;
		}
	elsif ($a eq "--no-secondaries") {
		$nosecondaries = 1;
		}
	elsif ($a eq "--pre-command") {
		$precommand = shift(@ARGV);
		}
	elsif ($a eq "--post-command") {
		$postcommand = shift(@ARGV);
		}
	elsif ($a eq "--skip-warnings") {
		$skipwarnings = 1;
		}
	elsif ($a =~ /^\-\-(.*)$/ && $plugin_args{$1}) {
		# Plugin-specific arg
		if ($plugin_args{$1}->{'novalue'}) {
			$plugin_values{$1} = "";
			}
		else {
			$plugin_values{$1} = shift(@ARGV);
			}
		}
	else {
		&usage("Unknown option $a");
		}
	}
if ($template eq "") {
	$template = &get_init_template($parentdomain);
	}
$tmpl = &get_template($template);
$plan = $planid ne '' ? &get_plan($planid) : &get_default_plan();
$plan || &usage("Plan does not exist");

if ($ip eq "allocate") {
	# Allocate IP now
	$virtalready && &usage("The --ip-already and --allocate-ip options are incompatible");
	%racl = $resel ? &get_reseller_acl($resel) : ();
	if ($racl{'ranges'}) {
		# Allocating from reseller's range
		$ip = &free_ip_address(\%racl);
		$ip || &usage("Failed to allocate IP address from reseller's ranges!");
		}
	else {
		# Allocating from template
		$tmpl->{'ranges'} ne "none" || &usage("The --allocate-ip option cannot be used unless automatic IP allocation is enabled - use --ip instead");
		$ip = &free_ip_address($tmpl);
		$ip || &usage("Failed to allocate IP address from ranges!");
		}
	}
elsif ($virt) {
	# Make sure manual IP specification is allowed
	$tmpl->{'ranges'} eq "none" || $config{'all_namevirtual'} || &usage("The --ip option cannot be used when automatic IP allocation is enabled - use --allocate-ip instead");
	}

# If no limit-related flags are given, assume from plan
if (!$tlimit && !$anylimits) {
	$tlimit = 1;
	}

# Make sure all needed args are set
$domain || &usage("Missing domain name");
$parentdomain || $pass || &usage("Missing password");
if (&has_home_quotas() && !$parentdomain) {
	$quota && $uquota || $tlimit || &usage("No quota specified");
	}
if ($parentdomain) {
	$feature{'unix'} && &usage("--unix option makes no sense for sub-servers");
	}
if ($aliasdomain) {
	foreach $f (keys %feature) {
		&indexof($f, @opt_alias_features) >= 0 ||
			&usage("--$f option makes no sense for alias servers");
		}
	}
if ($subdomain) {
	foreach $f (keys %feature) {
		&indexof($f, @opt_subdom_features) >= 0 ||
			&usage("--$f option makes no sense for sub-domains");
		}
	}

# Validate args and work out defaults for those unset
$domain = lc(&parse_domain_name($domain));
$err = &valid_domain_name($domain);
&usage($err) if ($err);
&lock_domain_name($domain);
foreach $d (&list_domains()) {
        usage($text{'setup_edomain4'}) if (lc($d->{'dom'}) eq lc($domain));
        }
if ($parentdomain) {
	$parent = &get_domain_by("dom", $parentdomain);
	$parent || &usage("Parent domain does not exist");
	$plan = &get_plan($parent->{'plan'});	# Parent overrides any selection
	$alias = $parent if ($aliasdomain);
	$subdom = $parent if ($subdomain);
	if ($subdomain) {
		$domain =~ /^(\S+)\.\Q$subdomain\E$/ ||
			&usage("Sub-domain $domain must be under the parent domain $subdomain");
		$subprefix = $1;
		}
	}

# Allow user and group names
if (!$parent) {
	if (!$user) {
		($user, $try1, $try2) = &unixuser_name($domain);
		$user || &usage(&text('setup_eauto', $try1, $try2));
		}
	else {
		$user =~ /^[^\t :]+$/ || &usage($text{'setup_euser2'});
		defined(getpwnam($user)) && &usage($text{'setup_euser'});
		}
	if (!$group) {
		($group, $gtry1, $gtry2) = &unixgroup_name($domain, $user);
		$group || &usage(&text('setup_eauto2', $try1, $try2));
		}
	else {
		$group =~ /^[^\t :]+$/ || &usage($text{'setup_egroup2'});
		defined(getgrnam($group)) &&
			&usage(&text('setup_egroup', $group));
		}
	}
$owner ||= $domain;

# Work out features, if using automatic mode.
# If the user asked for features from the plan but it doesn't define any,
# fall back to the global defaults.
$tfl = $plan->{'featurelimits'};
if ($planfeatures && $tfl) {
	# From limits on selected plan
	%flimits = map { $_, 1 } split(/\s+/, $tfl);
	%feature = ( 'virt' => $feature{'virt'} );
	%plugin = ( );
	foreach my $f (&list_available_features($parent, $alias, $subdom)) {
		if ($flimits{$f->{'feature'}} && $f->{'enabled'}) {
			if ($f->{'plugin'}) {
				$plugin{$f->{'feature'}} = 1;
				}
			else {
				$feature{$f->{'feature'}} = 1;
				}
			}
		}
	}
elsif ($deffeatures || $planfeatures && !$tfl) {
	# From global configured defaults
	%feature = ( 'virt' => $feature{'virt'} );
	%plugin = ( );
	foreach my $f (&list_available_features($parent, $alias, $subdom)) {
		if ($f->{'default'} && $f->{'enabled'}) {
			if ($f->{'plugin'}) {
				$plugin{$f->{'feature'}} = 1;
				}
			else {
				$feature{$f->{'feature'}} = 1;
				}
			}
		}
	}
scalar(keys %feature) || &usage("No virtual server features enabled");

if (!$parent) {
	# Make sure alias, database, etc limits are set properly
	!defined($mailboxlimit) || $mailboxlimit =~ /^[1-9]\d*$/ ||
		&usage($text{'setup_emailboxlimit'});
	!defined($dbslimit) || $dbslimit =~ /^[1-9]\d*$/ ||
		&usage($text{'setup_edbslimit'});
	!defined($aliaslimit) || $aliaslimit =~ /^[1-9]\d*$/ ||
		&usage($text{'setup_ealiaslimit'});
	!defined($domslimit) || $domslimit eq "*" ||
	   $domslimit =~ /^[1-9]\d*$/ ||
		&usage($text{'setup_edomslimit'});
	!defined($aliasdomslimit) || $aliasdomslimit =~ /^[1-9]\d*$/ ||
		&usage($text{'setup_ealiasdomslimit'});
	!defined($realdomslimit) || $realdomslimit =~ /^[1-9]\d*$/ ||
		&usage($text{'setup_erealdomslimit'});
	}

if (!$parent) {
	# Validate username
	&require_useradmin();
	$uerr = &useradmin::check_username_restrictions($user);
	if ($uerr) {
		&usage(&text('setup_eusername', $user, $uerr));
		}
	$user =~ /^[^\t :]+$/ || &usage($text{'setup_euser2'});
	&indexof($user, @banned_usernames) < 0 ||
		&usage(&text('setup_eroot', 'root'));
	}

# Validate quotas
if (&has_home_quotas() && !$parent && !$tlimit) {
        $quota =~ /^\d+$/ || &usage($text{'setup_equota'});
        $uquota =~ /^\d+$/ || &usage($text{'setup_euquota'});
        }

# Validate reseller
if (defined($resel)) {
	$parent && &usage("Reseller cannot be set for sub-servers");
	@resels = &list_resellers();
	($rinfo) = grep { $_->{'name'} eq $resel } @resels;
	$rinfo || &usage("Reseller $resel not found");
	}

$defip = &get_default_ip($resel);
if (!$alias) {
	if ($config{'all_namevirtual'}) {
		# Make sure the IP *is* assigned
		&check_ipaddress($ip) || &usage($text{'setup_eip'});
		if (!&check_virt_clash($ip)) {
			&usage(&text('setup_evirtclash2'));
			}
		}
	elsif ($virt) {
		&check_ipaddress($ip) || &usage($text{'setup_eip'});
		$clash = &check_virt_clash($ip);
		if ($virtalready) {
			# Make sure IP is already active
			$clash || &usage(&text('setup_evirtclash2'));
			if ($virtalready == 1) {
				# Don't allow clash with another domain
				local $already = &get_domain_by("ip", $ip);
				$already && &usage(&text('setup_evirtclash4',
						 $already->{'dom'}));
				}
			else {
				# The system's PRIMARY ip is being used by
				# this domain, so we can host a single SSL
				# virtual host on it.
				}
			}
		else {
			# Make sure the IP isn't assigned yet
			$clash && &usage(&text('setup_evirtclash'));
			}
		}
	}
else {
	$ip = $alias->{'ip'};
	}

# Validate style
if ($stylename) {
	($style) = grep { $_->{'name'} eq $stylename } &list_content_styles();
	$style || &usage("Style $stylename does not exist");
	$content || $style->{'nocontent'} || &usage("--content followed by some initial text for the website must be specified when using --style");
	if ($content =~ /^\//) {
		$content = &read_file_contents($content);
		$content || &usage("--content file does not exist");
		}
	$content =~ s/\r//g;
	$content =~ s/\\n/\n/g;
	}

if ($parent) {
	# User and group IDs come from parent
	$gid = $parent->{'gid'};
	$ugid = $parent->{'ugid'};
	$user = $parent->{'user'};
	$group = $parent->{'group'};
	$uid = $parent->{'uid'};
	}
else {
	# IDs are allocated later
	$uid = $ugid = $gid = undef;
	}

# Work out prefix if needed, and check it
$prefix ||= &compute_prefix($domain, $group, $parent, 1);
$prefix =~ /^[a-z0-9\.\-]+$/i || &usage($text{'setup_eprefix'});
$pclash = &get_domain_by("prefix", $prefix);
$pclash && &usage(&text('setup_eprefix3', $prefix, $pclash->{'dom'}));

# Build up domain object
%dom = ( 'id', &domain_id(),
	 'dom', $domain,
         'user', $user,
         'group', $group,
         'ugroup', $group,
         'uid', $uid,
         'gid', $gid,
         'ugid', $gid,
         'owner', $owner,
         'email', $parent ? $parent->{'email'} : $email,
         'name', $name,
         'ip', $config{'all_namevirtual'} ? $ip :
	       $virt ? $ip :
	       $alias ? $ip :
	       $sharedip ? $sharedip : $defip,
	 'dns_ip', defined($dns_ip) ? $dns_ip :
		   $virt || $config{'all_namevirtual'} ? undef
						       : &get_dns_ip(),
         'virt', $virt,
         'virtalready', $virtalready,
	 $parent ? ( 'pass', $parent->{'pass'} )
		 : ( 'pass', $pass,
         	     'quota', $quota,
		     'uquota', $uquota ),
	 'alias', $alias ? $alias->{'id'} : undef,
	 'subdom', $subdom ? $subdom->{'id'} : undef,
	 'source', 'create-domain.pl',
	 'template', $template,
	 'plan', $plan->{'id'},
	 'parent', $parent ? $parent->{'id'} : "",
	 $parent ? ( )
		 : ( 'mailboxlimit', $mailboxlimit,
		     'dbslimit', $dbslimit,
		     'aliaslimit', $aliaslimit,
		     'domslimit', $domslimit,
		     'aliasdomslimit', $aliasdomslimit,
		     'realdomslimit', $realdomslimit,
		     'bw_limit', $bw eq 'NONE' ? undef : $bw ),
	 'prefix', $prefix,
	 'reseller', $resel,
	 'nocreationmail', $nocreationmail,
	 'noslaves', $noslaves,
	 'nosecondaries', $nosecondaries,
	 'subprefix', $subprefix,
        );
if (!$parent) {
	if ($tlimit) {
		&set_limits_from_plan(\%dom, $plan);
		}
	&set_capabilities_from_plan(\%dom, $plan);
	}
$dom{'db'} = $db || &database_name(\%dom);
$dom{'emailto'} = $parent ? $parent->{'emailto'} :
		  $dom{'email'} ? $dom{'email'} :
		  $dom{'mail'} ? $dom{'user'}.'@'.$dom{'dom'} :
		  		 $dom{'user'}.'@'.&get_system_hostname();
foreach $f (@features) {
	$dom{$f} = $feature{$f} ? 1 : 0;
	}
foreach $f (@feature_plugins) {
	$dom{$f} = $plugin{$f} ? 1 : 0;
	}
&set_featurelimits_from_plan(\%dom, $plan);
&set_chained_features(\%dom, undef);

# Work out home directory
$dom{'home'} = &server_home_directory(\%dom, $parent);
if (defined($mysqlpass) && $config{'mysql'}) {
	$dom{'parent'} && &usage("The --mysql-pass flag can only be used for top-level virtual servers");
	&set_mysql_pass(\%dom, $mysqlpass);
	}
if (defined($postgrespass) && $config{'postgres'}) {
	$dom{'parent'} && &usage("The --postgres-pass flag can only be used for top-level virtual servers");
	&set_postgres_pass(\%dom, $postgrespass);
	}
&complete_domain(\%dom);

# Set plugin-defined command line args
foreach $f (@feature_plugins) {
	if ($dom{$f}) {
		$err = &plugin_call($f, "feature_args_parse",
				    \%dom, \%plugin_values);
		&usage($err) if ($err);
		}
	}

# Check for various clashes
$derr = &virtual_server_depends(\%dom);
&usage($derr) if ($derr);
$cerr = &virtual_server_clashes(\%dom);
&usage($cerr) if ($cerr);

# Check for warnings, unless overriding
@warns = &virtual_server_warnings(\%dom);
if (@warns) {
	print "The following possible problems were detected :\n\n";
	foreach $w (@warns) {
		print "  $w\n";
		}
	if (!$skipwarnings) {
		print "\n";
		print "The virtual server will not be created unless the --skip-warnings\n";
		print "flag is given.\n";
		exit(5);
		}
	}

# Do it
print "Beginning server creation ..\n\n";
$config{'pre_command'} = $precommand if ($precommand);
$config{'post_command'} = $postcommand if ($postcommand);
$err = &create_virtual_server(\%dom, $parent,
			      $parent ? $parent->{'user'} : undef);
if ($err) {
	print "$err\n";
	exit 1;
	}

if ($fwdto) {
	&$first_print(&text('setup_fwding', $in{'fwdto'}));
	&create_domain_forward(\%dom, $fwdto);
	&$second_print($text{'setup_done'});
	}

if ($style && $dom{'web'}) {
	&$first_print(&text('setup_styleing', $style->{'desc'}));
	&apply_content_style(\%dom, $style, $content);
	&$second_print($text{'setup_done'});
	}

&virtualmin_api_log(\@OLDARGV, \%dom);
print "All done!\n";

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Adds a new Virtualmin virtual server, with the settings and features\n";
print "specified on the command line.\n";
print "\n";
print "usage: create-domain.pl  --domain domain.name\n";
print "                         --pass password-for-unix-user\n";
print "                        [--parent domain.name | --alias domain.name |\n";
print "                         --superdom domain.name]\n";
print "                        [--desc description-for-domain]\n";
print "                        [--email contact-email]\n";
print "                        [--user new-unix-user]\n";
foreach $f (@features) {
	print "                        [--$f]\n" if ($config{$f});
	}
foreach $f (@feature_plugins) {
	print "                        [--$f]\n";
	}
print "                        [--default-features] | [--features-from-plan]\n";
print "                        [--allocate-ip | --ip virtual.ip.address |\n";
print "                         --shared-ip existing.ip.address]\n";
print "                        [--ip-already]\n";
print "                        [--dns-ip address | --no-dns-ip]\n";
print "                        [--max-doms domains|*]\n";
print "                        [--max-aliasdoms domains]\n";
print "                        [--max-realdoms domains]\n";
print "                        [--max-mailboxes boxes]\n";
print "                        [--max-dbs databases]\n";
print "                        [--max-aliases aliases]\n";
if (&has_home_quotas()) {
	print "                        [--quota quota-for-domain|UNLIMITED]\n";
	print "                        [--uquota quota-for-unix-user|UNLIMITED]\n";
	}
if ($config{'bw_active'}) {
	print "                        [--bandwidth bytes]\n";
	}
print "                        [--template \"name\"]\n";
print "                        [--plan \"name\"]\n";
print "                        [--limits-from-pla]\n";
print "                        [--prefix username-prefix]\n";
print "                        [--db database-name]\n";
print "                        [--fwdto email-address]\n";
print "                        [--reseller name]\n";
if ($virtualmin_pro) {
	print "                        [--style name]\n";
	print "                        [--content text|filename]\n";
	}
if ($config{'mysql'}) {
	print "                        [--mysql-pass password]\n";
	}
if ($config{'postgres'}) {
	print "                        [--postgres-pass password]\n";
	}
foreach $f (@feature_plugins) {
	if (&plugin_defined($f, "feature_args")) {
		foreach $a (&plugin_call($f, "feature_args")) {
			print "                        [--$a->{'name'}";
			if (!$a->{'novalue'}) {
				print " $a->{'value'}";
				}
			print "]\n";
			}
		}
	}
print "                        [--skip-warnings]\n";
exit(1);
}


