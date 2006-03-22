package UpdateBerlios;

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Request::Form;
use HTTP::Cookies;
use HTML::TreeBuilder;
use Data::Dumper;
use strict;

# Configuration.
my $LOGINACTION="https://developer.berlios.de/account/login.php";
my $EDITRELEASE="https://developer.berlios.de/project/admin/editreleases.php";

my %TYPE=
   ('deb'   => '1000',
    'rpm'   => '2000',
    'zip'   => '3000',
    'bz2'   => '3001',
    'gz'    => '3002',
    'exe'   => '4000',
    'srczip'   => '5000',
    'srcbz2'   => '5001',
    'srcgz'    => '5002',
    'srcrpm'   => '5100',
    'srcother' => '5900',
    'jpg'      => '8000',
    'txt'      => '8001',
    'html'     => '8002',
    'pdf'      => '8003',
    'other'    => '9999');

my %ARCH=
   ('x86'   => '1000',
    'ia64'  => '6000',
    'alpha' => '7000',
    'any'   => '8000',
    'ppc'   => '2000',
    'mips'  => '3000',
    'sparc' => '4000',
    'sparc64'  => '5000',
    'other' => '9999',
    'x86_64'   => '9000');

sub new 
{
   my ($class)=@_;
   my $self=
      { projurl => undef };
   bless $self, $class;
   return $self;
}

sub connect
{
   my ($self, $user, $passwd)=@_;
   chomp $user;
   chomp $passwd;
  
   $self->{ua}=new LWP::UserAgent;
   $self->{ua}->agent("Oolite-Updater/1.0");
   $self->{ua}->cookie_jar( {} );
   
   my $forms=$self->getForms($LOGINACTION);
   my $login=new HTTP::Request::Form($forms->[2], $LOGINACTION);

   $login->field('form_loginname', $user);
   $login->field('form_pw', $passwd);
   $login->field('stay_in_ssl', 1);

   my $res=$self->{ua}->request($login->press('login'));

   # test for session cookie to see if login worked
   if($self->{ua}->cookie_jar->as_string =~ /session_hash/)
   {
      print("Logged into BerliOS as $user\n");
      return 1;
   }
   print("Login failed");
   exit(255);
}

sub deleteFiles
{
   my ($self, $url)=@_;

   # The general idea here is to keep hitting Delete until there
   # are no more delete forms left (all files are gone).
   while(1)
   {
      my $forms=$self->getForms($url);
      
      # iterate through the list of forms to find one that lets
      # us delete.
      my $candidate=undef;
      my $delfound=0;
      foreach my $form (@$forms)
      {
         $candidate=new HTTP::Request::Form
            ($form, $EDITRELEASE);
         if($candidate->field("step3") eq "Delete File")
         {
            $delfound=1;
            last;
         }
      }
      if(!$delfound)
      {
         # Nothing more
         last;
      }

      # the html doesn't seem to parse properly so for deleting we have
      # to do this by hand!!
      my $reqstr="group_id=" . $candidate->field('group_id');
      $reqstr.="&release_id=" . $candidate->field('release_id');
      $reqstr.="&package_id=" . $candidate->field('package_id');
      $reqstr.="&file_id=" . $candidate->field('file_id');
      $reqstr.="&im_sure=1";
      $reqstr.="&step3=Delete File";
      my $req=HTTP::Request->new(POST => $url);
      $req->content_type('application/x-www-form-urlencoded');
      $req->content($reqstr);
      
      my $res=$self->{ua}->request($req);
      if($res->is_success)
      {
         print("Deleted file id " . $candidate->field('file_id') . "\n");
      }
      else
      {
         die("Delete failed!");
      }
   }
}

# call this as thing->addFiles("http://...", file1, file2, ...);
sub addFiles
{
   my $self=shift;
   my $url=shift;

   my $forms=$self->getForms($url); 
   my $fileform=new HTTP::Request::Form($forms->[2], $EDITRELEASE);
   if($fileform->field('step2') ne "1")
   {
      die("Unexpected value for step2: " . $fileform->field('step2'));
   }

   # the form module can't parse this form (probably because of the
   # repeated field names) so we do it by hand.
   my @params;
   while(my $filename=shift())
   {
      push @params, "file_list[]=$filename";
   }
   my $reqstr=join("&", @params);

   $reqstr.="&group_id=" . $fileform->field('group_id');
   $reqstr.="&package_id=" . $fileform->field('package_id');
   $reqstr.="&release_id=" . $fileform->field('release_id');
   $reqstr.="&step2=1";
   
   my $req=HTTP::Request->new(POST => $url);
   $req->content_type('application/x-www-form-urlencoded');
   $req->content($reqstr);
   my $res=$self->{ua}->request($req);
   if($res->is_success)
   {
      if(! grep /File(s) Added/, $res->content)
      {
         return undef;
      }
   }
   else
   {
      die("Request failed");
   }
   return ($fileform->field('group_id'), $fileform->field('package_id'),
           $fileform->field('release_id'));
}

sub setFileArchitectures
{
   my ($self, $url, $arch, $type)=@_;

   # make sure arch/type can be converted
   my $arch=$ARCH{$arch};
   my $type=$TYPE{$type};

   if(!defined($arch) || !defined($type))
   {
      print("Arch/type not found (arch was '$arch', type was '$type')\n");
      exit;
   }
   
   my $forms=$self->getForms($url);
   my $candidate=undef;
   my %fileIdList;

   # all we're doing is getting a list of all file_ids and changing
   # them en-masse.
   foreach my $form (@$forms)
   {
      $candidate=new HTTP::Request::Form
            ($form, $EDITRELEASE);
      if(length($candidate->field('file_id')) && 
         $candidate->field('step3') eq "1")
      {
         $fileIdList{$candidate->field('file_id')}=
            "group_id=" . $candidate->field('group_id') .
            "&release_id=" . $candidate->field('release_id') .
            "&package_id=" . $candidate->field('package_id') .
            "&file_id=" . $candidate->field('file_id') .
            "&step3=1&processor_id=$arch&type_id=$type" . 
            "&new_release_id=" . $candidate->field('release_id') .
            "&release_time=" . `date +"%Y-%m-%d"`;
      }
   }
 
   foreach my $fileId (keys %fileIdList)
   {
      print("Updating file_id $fileId...\n"); 
      my $req=HTTP::Request->new(POST => $url);
      $req->content_type('application/x-www-form-urlencoded');
      $req->content($fileIdList{$fileId});
      my $res=$self->{ua}->request($req);
      if($res->is_success)
      {
         if(! grep /File Updated/, $res->content)
         {
            print("Warning: possibly did not update file_id $fileId\n");
         }
      }
      else
      {
         die("Request failed");
      }
   }
}
   
sub getForms
{
   my ($self, $url)=@_;

   my $req=new HTTP::Request(GET => $url);
   my $res=$self->{ua}->request($req);
   my $tree=new HTML::TreeBuilder;
   $tree->parse($res->content);
   $tree->eof;

   # enumerate forms
   my @forms=$tree->find_by_tag_name('FORM')
         or die("No forms found at $url");
   return \@forms;
}

