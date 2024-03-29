#                  file:  Qtk/QuickTk.pm
#
#   Copyright (c) 2000 John Kirk. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
#   The latest version of this module should always be available
# at any CPAN (http://www.cpan.org) mirror, or from the author:
#              http://perl.dystanhays.com/jnk

package Qtk::QuickTk;

use strict;
use vars qw($VERSION @ISA @EXPORT_OK);

require Exporter;
require AutoLoader;

$VERSION=0.90;
@ISA=qw(Exporter AutoLoader);
@EXPORT_OK=qw(app createwidget showglobals logit logg);

require 5.002;
use English;       # for EVAL_ERROR
use Carp;
use FileHandle;    # nice to easily have filehandles as plain variables
use Tk;

my %proto=('menutypes'=>{'c'=>'command','m'=>'cascade','-'=>'separator',
                         'k'=>'checkbutton','r'=>'radiobutton',},
           'widgets'=>{},);

sub app;
sub createwidget;

sub _loadwidget;
sub _loadmenitm;
sub _bindevent;
sub _getargs;
sub _gettitle;
sub _getcommand;
sub _getsub;
sub _getini;

sub showglobals;
sub logit;
sub logg;

sub new {
  my ($that,$spec,$lname,$genonly)=@_;
  my $class=ref($that)||$that;
  my $me={_prop=>\%proto,%proto,};
  bless $me,$class;
  if(defined $genonly) {
    $$me{genonly}=$genonly;
  }
  if(defined $lname) {
    $$me{lname}=$lname;
    $$me{lfh}=new FileHandle ">$lname";
  }
  if(defined $spec) { # a spec was passed in; load it
    my $specref;
    if(!ref $spec) { # it's a filename (also handle case: '')
      die "can't read QuickTk spec file: $spec\n" unless -f $spec && -r _;
      use Text::TreeFile;
      my $hier=Text::TreeFile->new($spec);
      $specref=$$hier{top};
    } elsif(ref($spec) eq 'Text::TreeFile') {
      $specref=$$spec{top};
    } elsif(ref($spec) eq 'ARRAY' and scalar @$spec==2 and
            !ref $$spec[0] and ref($$spec[1]) eq 'ARRAY') {
      $specref=$spec;
    } else {
      die "can't make a new Qtk::QuickTk from spec: $spec\n";
    }
    _loadwidget($me,$specref);
    if(exists $$me{inicode} and defined $$me{inicode} and $$me{inicode}) {
      my $err=_docode($me,0,$$me{inicode});
      if($err) {
        die "failed to execute initialization code\n";
      }
    }
  }
  return $me;
}

sub app {
  my ($gen,$gname)=@_;
  my $name=$ARGV[0]
    or carp "Qtk::QuickTk::app() found no filename on the command line\n";
  my $iname=$name;
  my $oname;
  if(defined $gen and $gen ne 'nogen') {
    $oname=(defined $gname)?$gname:$name.'.pl';
    print "Qtk::QuickTk::app() logging generated perl-tk code";
    print " to file: $oname\n";
  }
  my $app=(defined $oname)?Qtk::QuickTk->new($iname,$oname)
                          :Qtk::QuickTk->new($iname);
  MainLoop;die "fell through MainLoop";
}

sub createwidget {
  my ($gl,$arg,$specname)=@_;
  my ($code,$err,$menidx,$ret);
  my %mt=%{$$gl{menutypes}};
  my $spec=$$gl{widgets}{$specname};
  die "couldn't find \"$specname\" widget to create\n" unless defined $spec;
  my ($level,$momname,$momidx,$name,$type,$cfg,$pak,$children)=@$spec;
  for($name,$type,$cfg,$pak) {
    s/\$(\d+)/$$arg[$1-1]/g;
  }
  if(defined $momidx) { # this is a menu item
    $code="\$\$w{${momname}_${momidx}_$$arg[0]}=\$\${momname}->$mt{$type}";
    if($type ne '-') {
      $code.="(-label=>\"$name\")";
    }
    $err=_docode($gl,$level,$code);
    $code='';
    die "failed to create menu item $momname/${name}_$$arg[0]($momidx)\n" if ($err);
    if($cfg) {
      $code="\$\$w{momname}_${momidx}_$$arg[0]}->configure($cfg)";
      $err=_docode($gl,$level,$code);
      $code='';
      if($err) {
        die "failed to configure $momname/$name(${momidx}_$$arg[0])\n";
      }
    }
    if(@$children) {
      $code="\$\$w{${momname}_${momidx}_$$arg[0]_menu}";
      $code.="=\$\$w{$momname}->Menu";
      $err=_docode($gl,$level,$code);
      $code='';
      if($err) {
        die "failed to create Menu: ${momname}_${momidx}_$$arg[0]_menu\n";
      }
      $code="\$\$w{${momname}_${momidx}_$$arg[0]}->configure(";
      $code.="-menu=>\$\$w{${momname}_${momidx}_$$arg[0]_menu})";
      $err=_docode($gl,$level,$code);
      my $errname="${momname}_$momidx/${momname}_${momidx}_$$arg[0]_menu";
      if($err) {
        die "failed to configure menu item $errname\n";
      }
    }
    $menidx=0;
    for(@$children) {
      _loadmenitm $gl,$_,$level+1,"${momname}_${momidx}_$$arg[0]_menu",$menidx;
      ++$menidx;
    }
  } else { # this is an ordinary widget
    $code="\$\$w{${name}_$$arg[0]}=\$\$w{$momname}->$type";
    $code.="($cfg)" if($cfg);
    $err=_docode($gl,$level,$code);
    $code='';
    if($err) {
      die "failed to create ${name}_$$arg[0]: $momname/$type\n";
    }
    if($type eq 'Menubutton') {
      $code="\$\$w{${name}_$$arg[0]_menu}=\$\$w{${name}_$$arg[0]}->Menu";
      $err=_docode($gl,$level,$code);
      $code='';
      if($err) {
        die "failed to create Menu ${name}_$$arg[0]_menu for Menubutton ${name}_$$arg[0]\n";
      }
      $code="\$\$w{${name}_$$arg[0]}->configure(-menu=>\$\$w{${name}_$$arg[0]_menu})";
      $err=_docode($gl,$level,$code);
      $code='';
      if($err) {
        die "failed to configure Menubutton ${name}_$$arg[0]\n";
      }
    }
    $menidx=0;
    for(@$children) {
      if($type ne 'Menubutton') {
        if(substr($$_[0],0,1) ne '<') {
          _loadwidget $gl,$_,$level+1,"${name}_$$arg[0]";
        } else {
          _bindevent $gl,$_,$level+1,"${name}_$$arg[0]";
        }
      } else {
        _loadmenitm $gl,$_,$level+1,"${name}_$$arg[0]_menu",$menidx;
        ++$menidx;
      }
    }
    return if($pak=~/^nopack/);
    $ret=($pak=~s/^(pack|place|grid),//)?$1:'pack';
    $code="\$\$w{${name}_$$arg[0]}->$ret($pak)";
    $err=_docode($gl,$level,$code);
    $code='';
    if($err) {
      die "failed to pack ${name}_$$arg[0]\n";
    }
  }
  
}

sub _loadwidget {
  my ($gl,$spec,$level,$momname)=@_;
  my ($cfg,$pak,$idx,$ret,$cre,$code,$err);
  my ($localname,$type,$tail)=split ' ',$$spec[0],3;
  $momname='' if not defined $momname;
  my $name=$momname.$localname;
  $level=0 if not defined $level;
  if($level==0) {
    $type='MainWindow' if $type=~/^(Toplevel|Frame)$/;
    if($type ne 'MainWindow') {
      die "Top level widget must be \"MainWindow\", not \"$type\"\n";
    }
    ($cre,$cfg,$pak)=_getargs($gl,0,$tail,{'ttl'=>\&_getttl,
                                           'ini'=>\&_getini,});
    if($cre ne 'create') {
      warn "ignoring 'nocreate' for MainWindow...\n";
    }
    if($pak and $pak ne 'nopack') {
      warn "Packing options ($pak) for MainWindow are being ignored...\n";
    }
    $code="\$\$w{$name}=$type->new";
    $err=_docode($gl,$level,$code);
    $code='';
    if($err) {
      die "failed to open MainWindow\n";
    }
    if($cfg) {
      $code="\$\$w{$name}->configure($cfg)";
      $err=_docode($gl,$level,$code);
      $code='';
      if($err) {
        die "failed to configure MainWindow\n";
      }
    }
    for(@{$$spec[1]}) {
      if(substr($$_[0],0,1) ne '<') {
        _loadwidget $gl,$_,$level+1,$name;
      } else {
        _bindevent $gl,$_,$level+1,$name;
      }
    }
    return;
  }
  if($type eq 'MainWindow') {
    $type='Toplevel';
  }
  if($type eq 'Toplevel') {
    ($cre,$cfg,$pak)=_getargs($gl,0,$tail,{'ttl'=>\&_getttl,});
  } elsif($type eq 'Menu') {
    ($cre,$cfg,$pak)=_getargs($gl,0,$tail,{});
  } else {
    ($cre,$cfg,$pak)=_getargs($gl,1,$tail,{'cmd'=>\&_getcmd,
                                           'sub'=>\&_getsub,});
  }
  if($cre ne 'create') {
    $$gl{widgets}{$name}=
      [$level,$momname,undef,$name,$type,$cfg,$pak,$$spec[1]];
    return;
  }
  $code="\$\$w{$name}=\$\$w{$momname}->$type";
  $code.="($cfg)" if($cfg);
  $err=_docode($gl,$level,$code);
  $code='';
  if($err) {
    die "failed to create $name: $momname/$type\n";
  }
  if($type eq 'Menubutton') {
    $code="\$\$w{${name}_menu}=\$\$w{$name}->Menu";
    $err=_docode($gl,$level,$code);
    $code='';
    $code="\$\$w{$name}->configure(-menu=>\$\$w{${name}_menu})";
    $err=_docode($gl,$level,$code);
    $code='';
    if($err) {
      die "failed to configure Menubutton\n";
    }
  }
  $idx=0;
  for(@{$$spec[1]}) {
    if($type ne 'Menubutton') {
      if(substr($$_[0],0,1) ne '<') {
        _loadwidget $gl,$_,$level+1,$name;
      } else {
        _bindevent $gl,$_,$level+1,$name;
      }
    } else {
      _loadmenitm $gl,$_,$level+1,"${name}_menu",$idx;++$idx;
    }
  }
  return if($pak=~/^nopack/);
  $ret=($pak=~s/^(pack|place|grid),//)?$1:'pack';
  $code="\$\$w{$name}->$ret($pak)";
  $err=_docode($gl,$level,$code);
  $code=''; 
  if($err) {
    die "failed to create menu item $momname/$name\n";
  }
}

sub _bindevent {
  my ($gl,$spec,$level,$momname)=@_;
  my ($event,$act)=split ' ',$$spec[0],2;
  my ($code,$err);
  $code="\$\$w{$momname}->bind(\'$event\'=>$act)";
  $err=_docode($gl,$level,$code);
  $code='';
  if($err) {
    die "failed to bind: $event\n";
  }
}

sub _docode {
  my ($gl,$level,$code)=@_;
  $code.=";\n";
  my $w=$$gl{widgets};
  $$gl{lfh}->print('  'x$level,$code) if(exists $$gl{lfh});
  $code.="1;\n";
  return undef if $$gl{genonly};
  my $ret=eval $code;
  warn $EVAL_ERROR if $EVAL_ERROR;
  $code='';
  return $EVAL_ERROR;
}

sub _getargs {
  my ($gl,$pakq,$inp,$cmds)=@_;
  my ($opt,$sep,$val,$cdr,@cfg,@pak);
# called five places: four in loadwidget() and one in loadmenitm()
  my $create=1;
  if($pakq) {
    while($inp!~/^\s*$/) {
      ($opt,$sep,$cdr)=($inp=~/^([^ :]*)([ :])(.*)$/);
      if(!defined $sep) {
        $opt=$inp;
        $inp='';
        $val='-empty-';
      } elsif($sep eq ' ') {
        $val='-empty-';
        $cdr=~s/^\s+//;
        $inp=$cdr;
      } else {
        ($val,$inp)=($cdr=~/^[']([^']*)[']\s*(.*)$/);
        if(!defined $val) {
          if(substr($cdr,0,1) eq ' ') {
            $val='';$cdr=~s/^\s+//;
            $inp=$cdr;
          } else {
            ($val,$inp)=split ' ',$cdr,2;
          }
        }
      }
      last if $opt eq '';

      if(!defined $val or $val eq '' or $val eq '-empty-') { # no $val
        if($opt eq 'nocreate') {
          $create=0;
        } elsif($opt=~/^nopack|pack|place|grid$/) {
          unshift @pak,$opt;
        } else {
        push @pak,"-$opt=>\"\"";
        }
      } else {                                              # we have $val
        if($val=~/^\$\$/) {
          push @pak,"-$opt=>$val";
        } elsif($val=~/^\$\d+/) {
          push @pak,"-$opt=>$val";
        } elsif($val=~/^\$/) {
          push @pak,"-$opt=>".'$$gl{'.substr($val,1).'}';
        } elsif($val=~/^\\/) {
          push @pak,"-$opt=>".'\\$$gl{'.substr($val,1).'}';
        } elsif($val eq "''") {
          push @pak,"-$opt=>$val";
        } elsif($val=~/^\[.*\]$/) {
          push @pak,"-$opt=>$val";
        } else {
          push @pak,"-$opt=>\"$val\"";
        }
      } # end of actions for a $val that is present
    } # end of loop on packing options
  } # end of stuff to do if this widget allows packing
  while(defined $inp and $inp!~/^\s*$/) {
    ($opt,$sep,$cdr)=($inp=~/^([^ :]*)([ :])(.*)$/);
    if(!defined $sep) {
      $opt=$inp;
      $inp='';
      $val='-empty-';
    } elsif($sep eq ' ') {
      $val='-empty-';
      $cdr=~s/^\s+//;
      $inp=$cdr;
    } else {
      ($val,$inp)=($cdr=~/^["]([^"]+)["]\s*(.*)$/) or
      ($val,$inp)=($cdr=~/^[']([^']+)[']\s*(.*)$/) or
      ($val,$inp)=($cdr=~/^([[][^\]]+[\]])\s*(.*)$/);
    }

    if(exists $$cmds{$opt}) {
      if(!defined $val) {
        $val=$cdr;
        $inp='';
      }
      $val='' if $val eq '-empty-';
      ($opt,$val)=&{$$cmds{$opt}}($gl,$opt,$val);
    } else {
      if(!defined $val) {
        if(substr($cdr,0,1) eq ' ') {
          $val='';
          $cdr=~s/^\s+//;
          $inp=$cdr;
        } else {
          ($val,$inp)=split ' ',$cdr,2;
        }
        if(!defined $val) {
          $val=$cdr;
          $inp='';
        }
      }

      if(defined $val and $val ne '') {
        if($val eq '-empty-') {
          $val='';
        } elsif($val=~/^\$\$/) {
          # leave $val alone
        } elsif($val=~/^\\\$\$/) {
          # leave $val alone
        } elsif($val=~/^\$\d+/) {
          # leave $val alone
        } elsif($val=~/^\$/) {
          $val='$$gl{'.substr($val,1).'}';
        } elsif($val=~/^\\/) {
          $val='\\$$gl{'.substr($val,1).'}';
        } elsif($val ne "''" and $val!~/^\[.*\]$/
            and $val!~/^\'.*\'$/ and $val!~/^\".*\"$/) {
          $val="\"$val\"";
        }
      }
    }
    last if !defined $opt or $opt eq '';
    push @cfg,($val ne '')?"-$opt=>".$val:"\"$opt\"";
  }
  return ($create?'create':'nocreate',
          join(',',@cfg),
          $pakq?join(',',@pak):'nopack');
}

sub _loadmenitm {
  my ($gl,$spec,$level,$momname,$momidx)=@_;
  my ($localname,$name,$type,$tail,$code,$err,$label);
  my $trans=1;
  my %mt=%{$$gl{menutypes}};
  ($localname,$type,$tail)=split ' ',$$spec[0],3;
  $name=$momname.$localname;
  if($type!~/^[-cmrk]$/) { $trans=0;
    if($type!~/^separator|command|cascade|radiobutton|checkbutton$/i) {
      die "unrecgnized menu item type: $type\n";
    }
  }
  my ($cre,$cfg,$pak)=_getargs($gl,0,$tail,{'cmd'=>\&_getcmd,
                                            'sub'=>\&_getsub,});
  if($cre ne 'create') {
    $$gl{widgets}{"${momname}_$momidx"}=
      [$level,$momname,$momidx,$name,$type,$cfg,$pak,$$spec[1]];
    return;
  }
  $code="\$\$w{${momname}_$momidx}=\$\$w{$momname}->";
  $code.=$trans?$mt{$type}:$type;
  if($type ne '-') {
    $cfg=~s/(-label=>[^,]+),?//;
    die "menu item $name has no label\n" if not defined $1;
    $code.="($1)";
  }
  $err=_docode($gl,$level,$code);
  $code='';
  die "failed to create menu item $momname/$name($momidx)\n" if($err);
  if($cfg) {
    $code="\$\$w{${momname}_$momidx}->configure($cfg)";
    $err=_docode($gl,$level,$code);
    $code='';
    if($err) {
      die "failed to configure $momname/$name($momidx)\n";
    }
  }
  if(@{$$spec[1]}) {
    $code="\$\$w{${momname}_${momidx}_menu}";
    $code.="=\$\$w{$momname}->Menu";
    $err=_docode($gl,$level,$code);
    $code='';
    if($err) {
      die "failed to create Menu: ${momname}_${momidx}_menu\n";
    }
    $code="\$\$w{${momname}_$momidx}->configure(";
    $code.="-menu=>\$\$w{${momname}_${momidx}_menu})";
    $err=_docode($gl,$level,$code);
    $code='';
    my $errname="${momname}_$momidx/${momname}_${momidx}_menu";
    if($err) {
      die "failed to create menu item $errname\n";
    }
  }
  my $idx=0;
  for(@{$$spec[1]}) {
    _loadmenitm $gl,$_,$level+1,"${momname}_${momidx}_menu",$idx;++$idx;
  }
}

sub _getttl {
  my ($gl,$opt,$inp)=@_;
  $opt='title';
  return ($opt,"\"$inp\"");
}

sub _getcmd {
  my ($gl,$opt,$inp)=@_;
  $opt='command';
  my ($cmd,$dummy,$args)=($inp=~/^([^( ]+)\s*([(](.*)[)])?$/);
  my $ocmd='[\&main::'.$cmd.',$gl,'.$args.']';
  return ($opt,$ocmd);
}

sub _getsub {
  my ($gl,$opt,$inp)=@_;
  $opt='command';
  my $ocmd='sub { '.$inp.' }';
  return ($opt,$ocmd);
}

sub _getini {
  my ($gl,$opt,$inp)=@_;
  $$gl{inicode}=$inp;
  return (undef,undef);
}

1;

__END__

=head1 NAME

Qtk::QuickTk - A Simpler Syntax for Perl-Tk GUI Building

=head1 SYNOPSIS

  use Tk;
  use Qtk::QuickTk

  # need to set $filename, e.g.:  my $filename='miniapp.qtk';

  my $app=Qtk::Quicktk->new($filename);
  die "QuickTk constructor unable to read GUI spec: $filename\n"
    unless defined $app;

  MainLoop;die "QuickTk fell through past MainLoop\n";

or, alternatively, make a QuickTk script directly executable, with
the following first line (see full demo script in EXAMPLES, below:

  exec /usr/bin/perl -M'Qtk::QuickTk=app' -e app $0;exit


=head1 REQUIRES

I<QuickTk> uses modules:   I<Text::TreeFile> (optionally), I<Tk>,
I<FileHandle>, I<Carp>, I<English>, I<Exporter> and I<Autoloader>.

=head1 DESCRIPTION

I<QuickTk> supports a simplified syntax for specifying GUI-based
applications using I<perl-tk> (module F<Tk.pm> and friends).  A companion
module, F<Text::TreeFile>, supports comments, include files, continuation
lines and special interpretation of a strict indentation convention
to indicate tree-like hierarchical nesting.  Each node of a QuickTk
GUI specification is a character string which succinctly and clearly
specifies the properties of a GUI widget or event binding.  Such
specification documents are quick and easy to write, read and maintain.

=head1 OPTIONS

The GUI specification can be provided to I<QuickTk> in any of several
forms, the generated code can be logged to a file, and execution of
the code can be avoided, to allow code-generation only.

=head1 EXAMPLE

  -------------- executable as a shell script -------------------------------
  exec /usr/bin/perl -M'Qtk::QuickTk=app' -e app $0;exit
  #   file:  miniapp

  m MainWindow      title:'QuickTk Minimal Demo'
    mb Frame        side:top fill:x :
      f Menubutton  side:left       : text:File
        o c         label:Open sub:my($wid)=@_;
                      ...my $out=$$w{mts};my $tf=$$w{tf};
                      ...$$gl{efile}=$tf->Show;$$gl{eww}=0;
                      ...my $fh=new FileHandle "<$$gl{efile}";
                      ...while(<$fh>) { $out->insert('end',$_); }
                      ...close $fh;$out->yview('1.0');print "ok 2\n";
        q c         label:Quit sub:print "ok 8\n";exit;
      t Menubutton  side:left       : text:Tool
        d c         label:'Directory Listing'
                      ... sub:$$gl{widgets}{mts}->insert('end',
                      ...  `pwd`);$$gl{widgets}{mts}->insert('end',
                      ...  `ls -alF`);print "ok 3\n";
        s c         label:Satisfaction sub:print "ok 4\n";
      h Menubutton  side:right      : text:Help
        a c         label:About sub:$$gl{widgets}{mts}->insert('end',
                      ... 'this is a demo of perl module Qtk::QuickTk');
                      ... print "ok 5\n";
    tb Frame        side:top fill:x :
      d Button      side:left       : text:Dir
                      ... sub:$$w{mts}->insert('end',`ls -alF`);
                      ... print "ok 6\n";
      q Button      side:left       : text:Geom sub:$$w{mts}->insert('end',
                      ... "geom: ".$$w{m}->geometry."\n");
                      ... print "ok 7\n";
    ts Scrolled     side:top fill:both expand:1 : Text: scrollbars:osoe
    tf FileSelect   nopack                           : directory:.
  -------------- end of executable shell script example ---------------------

=head1 FILE FORMAT

By default, F<Qtk::QuickTk> uses the F<Text::TreeFile> module to read a
file containing a GUI specification, in the I<QuickTk> mini-language.
The low-level format of this file is as follows.  Each widget is
specified in a node of the tree in such a file.  The language for
widget specifications is described further below.

The file format supported relies upon indentation of text strings,
to indicate hierarchical nesting for the tree structure.  Strict
indentation (of two space characters per nesting level) is used to
represent parent-child structure.

=head2 Comments

A line consisting exclusively of whitespace, or a line beginning with
either the pound-sign ("#"), the semicolon (";"), or the forward slash
("/") character will be ignored as a comment.    In the very first line
of a file, the initial characters, "exec ", will indicate a comment line.

=head2 Continuation Lines

A line beginning with whitespace followed by three period (".")
characters, will be concatenated to the previous line, as a
continuation.  The preceding end-of-line, the initial whitespace and
the ellipsis ("...") will be removed and otherwise ignored, to allow
long strings to be represented within line-length constraints.

=head2 Include Files

In addition, any line consisting of indentation followed by "include"
will be interpreted as a file-include request.  In this case, succeeding
whitespace followed by a file specification will cause the contents of
the named file to be substituted at that point in the tree.  The included
file will be sought in the same directory as the file including it.

=head1 WIDGET SPECIFICATIONS

The basic format for GUI widget specifications is a text string that
has two parts.  The first is an ID section which identifies the widget,
and the second is an arguments section which provides the specifics of
how the widget is to be configured.

=head2 Widget ID

There are four kinds of specifications, each with a variation in the
details of these two parts.  In the most common case (that for B<MainWindow>
and most other widgets), the ID section is made of two subparts.  First
is the name your script can use to reference the widget later, and second
is the widget type name, chosen from the many available in the Tk widget
library (e.g. B<Button>, B<MainWindow>, B<Menubutton>).  In the special case
of a menu item, the second part of the ID section can be a single letter
identifying one of five types of available menu items, for short, or the
name of the type itself.  The name subpart must be unique only within the
same level of indentation under a parent widget, because the name you will
use to refer to the widget will usually (automatically) be the concatenation
of its name with all its ancestors' names.

  For specifications of bindings of events to actions, the ID part is a
single event identifier enclosed in angle brackets ("E<lt>" and "E<gt>").

See L<"EXAMPLES">, or L<Qtk::QuickTk::scripts(3pm)>, for clarification.

Here are samples of each of the four kinds of specifications:

      m    MainWindow                title:'QuickTk Demo'
      f    Menubutton    side:left : text:File
      o    c                         label:Open sub:exit;
      <CR>                           sub:$$gl{command}=$$gl{inputline};

=head2 Widget Arguments

Each of the four kinds of specifications can have arguments provided.
There are two categories of arguments, and these are separated by a colon
(":") character which, itself, is surrounded by spaces.  The first type
of arguments is the "packing options" and the second is the "configuration
options".  The packing options (and the colon delimiter) are not specified
for three of the four kinds of specifications.  These are the MainWindow,
the menu items, and the event bindings.  The packing options are used for
the most common widget specifications -- the ones for generic widgets --
so these specifications will always have the space-surrounded colon
delimiter unless no configuration option arguments need to be specified.

To write these specifications you must be acquainted with the perl-tk
(module F<Tk.pm>) library of widgets and how to use it.  The QuickTk
module provides a good many simplifications of syntax, though, and
details of these are described in L<Qtk::QuickTk::details(3pm)>,
L<Qtk::QuickTk::scripts>, and demonstrated in the example scripts.

=head1 CAVEATS

B<QuickTk> provides none of the GUI-building widgets, functions or other
facilities.  It provides only for simplified syntax for accessing the
capabilities and features of F<perl-tk> (the perl module, B<Tk(3pm)>
and friends), so familiarity with those materials is prerequisite to
using B<QuickTk>.

=head1 AUTHOR

John Kirk E<lt>F<johnkirk@dystanhays.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 2000 John Kirk. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Text::TreeFile(3pm)> - for the low-level file format it supports,

L<Qtk::QuickTk::scripts(3pm)> - for exhaustive description of the syntax,

L<Qtk::QuickTk::details(3pm)> - for precise definition of usage details,

L<Qtk::QuickTk::internals(3pm)> - for implementation details,

L<Tk::UserGuide(3pm)> - for an introduction to perl-tk,

L<widget(1)> - for examples of most of the perl-tk widgets, etc.,

and F<http://perl.dystanhays.com/jnk> - for related material on this module.

=head1 BUGS

Uses (deprecated for libraries) F<English(3pm)>, which should be removed.

Also, exceptions are handled poorly, inconsistently and unclearly.  The
F<Carp(3pm)> module should be used, the behavior should be made more clear,
and the exceptions should be handled in a consistent manner.

Documentation is incomplete (although the module code is very short, thus
somewhat accessible) and examples are not very thorough.

The code is ready for an overhaul to reduce near-duplication and improve
modularity.

=cut

sub showglobals {
  my ($gl)=@_;
  return if(!exists($$gl{lfh}));
  for(keys %{$gl}) {
    $$gl{lfh}->print("$_: $$gl{$_}\n");
  }
}

sub logg {
  my ($gl,$txt)=@_;
  return if (!exists($$gl{lfh}));
  my $lfh=$$gl{lfh};
  $lfh->print($txt);
}

sub logit {
  my ($gl,$level,$code)=@_;
  $$gl{lfh}->print('  'x$level,$code);
}
