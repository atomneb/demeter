package  Demeter::UI::Artemis::History;

=for Copyright
 .
 Copyright (c) 2006-2011 Bruce Ravel (bravel AT bnl DOT gov).
 All rights reserved.
 .
 This file is free software; you can redistribute it and/or
 modify it under the same terms as Perl itself. See The Perl
 Artistic License.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

use strict;
use warnings;
use Cwd;
use File::Path qw(rmtree);
use List::MoreUtils qw(minmax);

use Wx qw( :everything );
use Wx::Event qw(EVT_CLOSE EVT_LISTBOX EVT_CHECKLISTBOX EVT_BUTTON EVT_RADIOBOX
		 EVT_ENTER_WINDOW EVT_LEAVE_WINDOW EVT_CHOICE EVT_RIGHT_DOWN EVT_MENU);
use base qw(Wx::Frame);

sub new {
  my ($class, $parent) = @_;
  my $this = $class->SUPER::new($parent, -1, "Artemis [History]",
				wxDefaultPosition, wxDefaultSize,
				wxMINIMIZE_BOX|wxCAPTION|wxSYSTEM_MENU|wxCLOSE_BOX);
  EVT_CLOSE($this, \&on_close);
  $this->{statusbar} = $this->CreateStatusBar;
  $this->{statusbar} -> SetStatusText(q{ });

  my $box = Wx::BoxSizer->new( wxHORIZONTAL );

  my $left = Wx::BoxSizer->new( wxVERTICAL );
  $box -> Add($left, 1, wxGROW|wxALL, 5);

  my $listbox       = Wx::StaticBox->new($this, -1, 'Fit history', wxDefaultPosition, wxDefaultSize);
  my $listboxsizer  = Wx::StaticBoxSizer->new( $listbox, wxVERTICAL );

  $this->{list} = Wx::CheckListBox->new($this, -1, wxDefaultPosition, [-1,500],
				   [], wxLB_SINGLE);
  $this->{list}->{datalist} = [];
  $listboxsizer -> Add($this->{list}, 1, wxGROW|wxALL, 0);
  $left -> Add($listboxsizer, 0, wxGROW|wxALL, 5);
  EVT_LISTBOX($this, $this->{list}, sub{OnSelect(@_)} );
  EVT_CHECKLISTBOX($this, $this->{list}, sub{OnCheck(@_), $_[1]->Skip} );
  EVT_RIGHT_DOWN($this->{list}, sub{OnRightDown(@_)} );
  EVT_MENU($this->{list}, -1, sub{ $this->OnPlotMenu(@_)    });
  $this-> mouseover('list', "Right click on the fit list for a menu of additional actions.");

  my $markbox      = Wx::StaticBox->new($this, -1, 'Mark fits', wxDefaultPosition, wxDefaultSize);
  my $markboxsizer = Wx::StaticBoxSizer->new( $markbox, wxHORIZONTAL );
  $left -> Add($markboxsizer, 0, wxGROW|wxALL, 0);


  $this->{all} = Wx::Button->new($this, -1, 'All', wxDefaultPosition, wxDefaultSize, wxBU_EXACTFIT);
  $markboxsizer -> Add($this->{all}, 1, wxALL, 0);
  $this->{none} = Wx::Button->new($this, -1, 'None', wxDefaultPosition, wxDefaultSize, wxBU_EXACTFIT);
  $markboxsizer -> Add($this->{none}, 1, wxLEFT|wxRIGHT, 2);
  $this->{regexp} = Wx::Button->new($this, -1, 'Regexp', wxDefaultPosition, wxDefaultSize, wxBU_EXACTFIT);
  $markboxsizer -> Add($this->{regexp}, 1, wxALL, 0);
  EVT_BUTTON($this, $this->{all},  sub{mark(@_, 'all')});
  $this-> mouseover('all', "Mark all fits.");
  EVT_BUTTON($this, $this->{none}, sub{mark(@_, 'none')});
  $this-> mouseover('none', "Unmark all fits.");
  EVT_BUTTON($this, $this->{regexp}, sub{mark(@_, 'regexp')});
  $this-> mouseover('regexp', "Mark by regular expression.");

  $this->{close} = Wx::Button->new($this, wxID_CLOSE, q{}, wxDefaultPosition, wxDefaultSize);
  $left -> Add($this->{close}, 0, wxGROW|wxLEFT, 1);
  EVT_BUTTON($this, $this->{close}, \&on_close);
  $this-> mouseover('close', "Hide the history window.");

  my $right = Wx::BoxSizer->new( wxVERTICAL );
  $box -> Add($right, 0, wxGROW|wxALL, 5);

  my $nb  = Wx::Notebook->new($this, -1, wxDefaultPosition, wxDefaultSize, wxNB_TOP);
  $right -> Add($nb, 1, wxGROW|wxALL, 0);

  my $logpage = Wx::Panel->new($nb, -1);
  my $logbox  = Wx::BoxSizer->new( wxHORIZONTAL );
  $logpage->SetSizer($logbox);

  my $reportpage = Wx::Panel->new($nb, -1);
  my $reportbox  = Wx::BoxSizer->new( wxVERTICAL );
  $reportpage->SetSizer($reportbox);

  my $plottoolpage = Wx::ScrolledWindow->new($nb, -1);
  my $plottoolbox  = Wx::BoxSizer->new( wxVERTICAL );
  $plottoolpage -> SetSizer($plottoolbox);
  $plottoolpage -> SetScrollbars(20, 20, 50, 50);
  $this->{plottool} = $plottoolpage;
  $this->{scrollbox} = $plottoolbox;

  ## -------- text box for log file
  $this->{log} = Wx::TextCtrl->new($logpage, -1, q{}, wxDefaultPosition, [550, -1],
				   wxTE_MULTILINE|wxTE_READONLY|wxHSCROLL);
  $this->{log} -> SetFont( Wx::Font->new( 9, wxTELETYPE, wxNORMAL, wxNORMAL, 0, "" ) );
  $logbox -> Add($this->{log}, 1, wxGROW|wxALL, 5);

  ## -------- controls for writing reports on fits
  my $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $reportbox -> Add($controls, 0, wxGROW|wxALL, 0);
  $this->{summarize} = Wx::Button->new($reportpage, -1, "Sumarize marked fits");
  $controls->Add($this->{summarize}, 1, wxALL, 5);
  EVT_BUTTON($this, $this->{summarize}, sub{summarize(@_)});
  $this-> mouseover('summarize', "Write a short summary of each marked fit.");

  my $repbox      = Wx::StaticBox->new($reportpage, -1, 'Report on a parameter', wxDefaultPosition, wxDefaultSize);
  my $repboxsizer = Wx::StaticBoxSizer->new( $repbox, wxVERTICAL );
  $reportbox -> Add($repboxsizer, 0, wxGROW|wxALL, 5);

  $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $repboxsizer -> Add($controls, 0, wxGROW|wxALL, 5);
  my $label = Wx::StaticText->new($reportpage, -1, "Select parameter: ");
  $controls->Add($label, 0, wxTOP, 9);
  $this->{params} = Wx::Choice->new($reportpage, -1, wxDefaultPosition, wxDefaultSize, ["Statistcal parameters"]);
  $controls->Add($this->{params}, 0, wxALL, 5);
  EVT_CHOICE($this, $this->{params}, sub{write_report(@_)});
  $this-> mouseover('params', "Write and plot a report on the statistical parameters or on the chosen fitting parameter.");

  $this->{doreport} = Wx::Button->new($reportpage, -1, "Write report");
  $controls->Add($this->{doreport}, 0, wxALL, 5);
  EVT_BUTTON($this, $this->{doreport}, sub{write_report(@_)});
  $this-> mouseover('doreport', "Write and plot a report on the statistical parameters or on the chosen fitting parameter.");

  $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $repboxsizer -> Add($controls, 0, wxGROW|wxALL, 5);
  $this->{plotas} = Wx::RadioBox->new($reportpage, -1, "Plot statistics using", wxDefaultPosition, wxDefaultSize,
				      ["Reduced chi-square", "R-factor", "Happiness"],
				      1, wxRA_SPECIFY_ROWS);
  $controls->Add($this->{plotas}, 0, wxALL, 0);
  $this-> mouseover('plotas', "Specify which column will be plotted after generating a statistics report.");

  $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $repboxsizer -> Add($controls, 0, wxGROW|wxLEFT, 5);
  $this->{showy} = Wx::CheckBox->new($reportpage, -1, "Show y=0");
  $controls->Add($this->{showy}, 0, wxALL, 0);
  $this-> mouseover('showy', "Check this button to force the report plot to scale the plot such that the y axis starts at 0");

  $this->{report} = Wx::TextCtrl->new($reportpage, -1, q{}, wxDefaultPosition, [550, -1],
				   wxTE_MULTILINE|wxTE_READONLY|wxHSCROLL);
  $this->{report} -> SetFont( Wx::Font->new( 9, wxTELETYPE, wxNORMAL, wxNORMAL, 0, "" ) );
  $reportbox -> Add($this->{report}, 1, wxGROW|wxALL, 5);

  $controls = Wx::BoxSizer->new( wxHORIZONTAL );
  $reportbox -> Add($controls, 0, wxGROW|wxALL, 0);
  $this->{savereport} = Wx::Button->new($reportpage, -1, "Save report");
  $controls->Add($this->{savereport}, 1, wxALL, 5);
  EVT_BUTTON($this, $this->{savereport}, sub{savereport(@_)});
  $this-> mouseover('savereport', "Save the report contents to a file.");


  $nb -> AddPage($logpage,      "Log file", 1);
  $nb -> AddPage($reportpage,   "Reports", 0);
  $nb -> AddPage($plottoolpage, "Plot tool", 0);

  $this->SetSizerAndFit($box);
  return $this;
};

sub mouseover {
  my ($self, $widget, $text) = @_;
  EVT_ENTER_WINDOW($self->{$widget}, sub{$self->{statusbar}->PushStatusText($text); $_[1]->Skip});
  EVT_LEAVE_WINDOW($self->{$widget}, sub{$self->{statusbar}->PopStatusText if ($self->{statusbar}->GetStatusText eq $text); $_[1]->Skip});
};

sub OnSelect {
  my ($self, $event) = @_;
  my $fit = $self->{list}->GetIndexedData($self->{list}->GetSelection);
  return if not defined $fit;
  $self->put_log($fit);
  $self->set_params($fit);
};
sub OnCheck {
  #print "check: ", join(" ", @_), $/;
  1;
};

use Readonly;
Readonly my $FIT_RESTORE      => Wx::NewId();
Readonly my $FIT_SAVE	      => Wx::NewId();
Readonly my $FIT_EXPORT	      => Wx::NewId();
Readonly my $FIT_DISCARD      => Wx::NewId();
Readonly my $FIT_DISCARD_MANY => Wx::NewId();

sub OnRightDown {
  my ($self, $event) = @_;
  return if $self->IsEmpty;
  #$self->Deselect($self->GetSelection);
  #$self->SetSelection($self->HitTest($event->GetPosition));
  #$self->GetParent->OnSelect($event);
  #my $name = $self->GetStringSelection;
  my $position  = $self->HitTest($event->GetPosition);
  $self->GetParent->{_position} = $position; # need a way to remember where the click happened in methods called from OnPlotMenu
  ($position = $self->GetCount - 1) if ($position == -1);
  my $name = $self->GetString($position);
  my $menu = Wx::Menu->new(q{});
  $menu->Append($FIT_RESTORE, "Restore fitting model from \"$name\"");
  $menu->Append($FIT_SAVE,    "Save log file for \"$name\"");
  $menu->Append($FIT_EXPORT,  "Export \"$name\"");
  $menu->Append($FIT_DISCARD, "Discard \"$name\"");
  $menu->AppendSeparator;
  $menu->Append($FIT_DISCARD_MANY, "Discard marked fits");
  $menu->Enable($FIT_EXPORT,0);
  $menu->Enable($FIT_DISCARD_MANY,0);
  $self->PopupMenu($menu, $event->GetPosition);
};

sub OnPlotMenu {
  my ($self, $list, $event) = @_;
  my $id = $event->GetId;
 SWITCH: {
    ($id == $FIT_RESTORE) and do {
      $self->restore($self->{_position});
      last SWITCH;
    };
    ($id == $FIT_SAVE)    and do {
      $self->savelog($self->{_position});
      last SWITCH;
    };
    ($id == $FIT_EXPORT)  and do {
      $self->export($self->{_position});
      last SWITCH;
    };
    ($id == $FIT_DISCARD) and do {
      $self->discard('selected', $self->{_position});
      last SWITCH;
    };
    ($id == $FIT_DISCARD_MANY) and do {
      $self->discard('all');
      last SWITCH;
    };
  };
};

sub mark {
  my ($self, $event, $how) = @_; # how = all|none|marked
  my $re;
  if ($how eq 'regexp') {
    my $ted = Wx::TextEntryDialog->new( $self, "Mark fits matching this regular expression:", "Enter a regular expression", q{}, wxOK|wxCANCEL, Wx::GetMousePosition);
    if ($ted->ShowModal == wxID_CANCEL) {
      $self->status("Fit marking cancelled.");
      return;
    };
    my $regex = $ted->GetValue;
    my $is_ok = eval '$re = qr/$regex/';
    if (not $is_ok) {
      $self->{PARENT}->status("Oops!  \"$regex\" is not a valid regular expression");
      return;
    };
  };
  foreach my $i (0 .. $self->{list}->GetCount-1) {
    my $onoff = 0;
    if ($how eq 'regexp') {
      $onoff = ($self->{list}->GetIndexedData($i)->name =~ m{$re}) ? 1 : $self->{list}->IsChecked($i);
    } else {
      $onoff = ($how eq 'all') ? 1 : 0;
    };
    $self->{list}->Check($i, $onoff);
  };
};


sub on_close {
  my ($self) = @_;
  $self->Show(0);
  $self->GetParent->{toolbar}->ToggleTool(3, 0);
};

sub put_log {
  my ($self, $fit) = @_;
  my $busy = Wx::BusyCursor -> new();
  Demeter::UI::Artemis::LogText -> make_text($self->{log}, $fit);
  undef $busy;
};

sub set_params {
  my ($self, $fit) = @_;
  $self->{params}->Clear;
  $self->{params}->Append('Statistcal parameters');
  foreach my $g (sort {$a->name cmp $b->name} @{$fit->gds}) {
    $self->{params}->Append($g->name);
  };
  $self->{params}->SetStringSelection('Statistcal parameters');
};

sub mark_all_if_none {
  my ($self) = @_;
  my $count = 0;
  foreach my $i (0 .. $self->{list}->GetCount-1) {
    ++$count if $self->{list}->IsChecked($i);
  };
  $self->mark(q{}, 'all') if (not $count);
};

sub write_report {
  my ($self, $event) = @_;
  return if $self->{list}->IsEmpty;
  $self->mark_all_if_none;

  ## -------- generate report and enter it into text box
  $self->{report}->Clear;
  my $param = $self->{params}->GetStringSelection;
  (my $pp = $param) =~ s{_}{\\_}g;
  if ($param eq 'Statistcal parameters') {
    $self->{report}->AppendText($Demeter::UI::Artemis::demeter->template('fit', 'report_head_stats'));
  } else {
    $self->{report}->AppendText($Demeter::UI::Artemis::demeter->template('fit', 'report_head_param', {param=>$param}));
  };
  my @x = ();
  foreach my $i (0 .. $self->{list}->GetCount-1) {
    next if not $self->{list}->IsChecked($i);
    my $fit = $self->{list}->GetIndexedData($i);
    push @x, $fit->fom;
    if ($param eq 'Statistcal parameters') {
      $self->{report}->AppendText($fit->template('fit', 'report_stats'));
    } else {
      my $g = $fit->fetch_gds($param);
      next if not $g;
      $fit->mo->fit($fit);
      $self->{report}->AppendText($g->template('fit', 'report_param'));
      $fit->mo->fit(q{});
    };
  };

  ## -------- plot!
  my ($xmin, $xmax) = minmax(@x);
  my $delta = ($xmax-$xmin)/5;
  ($xmin, $xmax) = ($xmin-$delta, $xmax+$delta);
  $Demeter::UI::Artemis::demeter->po->start_plot;
  my $tempfile = $Demeter::UI::Artemis::demeter->po->tempfile;
  open my $T, '>'.$tempfile;
  print $T $self->{report}->GetValue;
  close $T;
  if ($param eq 'Statistcal parameters') {
    my $col = $self->{plotas}->GetSelection + 2;
    $Demeter::UI::Artemis::demeter->dispose($Demeter::UI::Artemis::demeter->template('plot', 'plot_stats', {file=>$tempfile, xmin=>$xmin, xmax=>$xmax, col=>$col, showy=>$self->{showy}->GetValue}), 'plotting');
  } else {
    $Demeter::UI::Artemis::demeter->dispose($Demeter::UI::Artemis::demeter->template('plot', 'plot_file', {file=>$tempfile, xmin=>$xmin, xmax=>$xmax, param=>$pp, showy=>$self->{showy}->GetValue}), 'plotting');
  };
  $self->status("Reported on $param");
};

sub summarize {
  my ($self, $event) = @_;
  return if $self->{list}->IsEmpty;
  $self->mark_all_if_none;
  my $text = q{};
  foreach my $i (0 .. $self->{list}->GetCount-1) {
    next if not $self->{list}->IsChecked($i);
    my $fit = $self->{list}->GetIndexedData($i);
    $text .= $fit -> summary;
  };
  return if (not $text);
  $self->{report}->Clear;
  $self->{report}->SetValue($text)
};
sub savereport {
  my ($self, $event) = @_;
  my $fd = Wx::FileDialog->new( $self, "Save log file", cwd, "report.txt",
				"Text files (*.txt)|*.txt",
				wxFD_SAVE|wxFD_CHANGE_DIR, #|wxFD_OVERWRITE_PROMPT,
				wxDefaultPosition);
  if ($fd->ShowModal == wxID_CANCEL) {
    $self->status("Not saving report.");
    return;
  };
  my $fname = File::Spec->catfile($fd->GetDirectory, $fd->GetFilename);
  return if $self->overwrite_prompt($fname); # work-around gtk's wxFD_OVERWRITE_PROMPT bug (5 Jan 2011)
  open my $R, '>', $fname;
  print $R $self->{report}->GetValue;
  close $R;
  $self->status("Wrote report to '$fname'.");
};

sub restore {
  my ($self, $position) = @_;
  ($position = $self->{list}->GetSelection) if not defined ($position);
  my $busy = Wx::BusyCursor -> new();
  Demeter::UI::Artemis::Project::discard_fit(\%Demeter::UI::Artemis::frames);
  my $fit = $self->{list}->GetIndexedData($position);
  Demeter::UI::Artemis::Project::restore_fit(\%Demeter::UI::Artemis::frames, $fit);
  undef $busy;
  $self->status("Restored ".$self->{list}->GetString($position));
};

sub discard {
  my ($self, $how, $position) = @_;
  ($position = $self->{list}->GetSelection) if not defined ($position);
  my $thisfit = $self->{list}->GetIndexedData($position);
  my $name = $thisfit->name;

  ## -------- remove this fit from the fit_order hash and rewrite the order file
  delete $Demeter::UI::Artemis::fit_order{order}{$thisfit->group};
  Demeter::UI::Artemis::update_order_file(1);
  #my $string .= YAML::Tiny::Dump(%Demeter::UI::Artemis::fit_order);
  #open(my $ORDER, '>'.$Demeter::UI::Artemis::frames{main}->{order_file});
  #print $ORDER $string;
  #close $ORDER;

  ## -------- remove this fit from the fit list
  if ($position == $self->{list}->GetCount-1) { # last position
    $self->{list}->SetSelection($position-1);
    $self->OnSelect;
  } elsif ($self->{list}->GetCount == 1) {      # only position
    $self->{list}->SetSelection(wxNOT_FOUND);
  } else {			                # all others
    $self->{list}->SetSelection($position+1);
    $self->OnSelect;
  };
  $self->{list}->DeleteData($position);

  ## -------- destroy the Fit object and delete its folder in stash space
  $thisfit->DEMOLISH;
  my $folder = File::Spec->catfile($Demeter::UI::Artemis::frames{main}->{project_folder}, 'fits', $thisfit->group);
  rmtree($folder);
  Demeter::UI::Artemis::modified(1);

  $self->status("discarded $name");
};

sub savelog {
  my ($self, $position) = @_;
  ($position = $self->{list}->GetSelection) if not defined ($position);
  my $fit = $self->{list}->GetIndexedData($position);

  (my $pref = $fit->name) =~ s{\s+}{_}g;
  my $fd = Wx::FileDialog->new( $self, "Save log file", cwd, $pref.q{.log},
				"Log files (*.log)|*.log",
				wxFD_SAVE|wxFD_CHANGE_DIR, #|wxFD_OVERWRITE_PROMPT,
				wxDefaultPosition);
  if ($fd->ShowModal == wxID_CANCEL) {
    $self->status("Not saving log file.");
    return;
  };
  my $fname = File::Spec->catfile($fd->GetDirectory, $fd->GetFilename);
  return if $self->overwrite_prompt($fname); # work-around gtk's wxFD_OVERWRITE_PROMPT bug (5 Jan 2011)
  $fit->logfile($fname);
  $self->status("Wrote log file to '$fname'.");
};

sub export {
  my ($self, $position) = @_;
  ($position = $self->{list}->GetSelection) if not defined ($position);

  $self->status("export ".$self->{list}->GetString($position)."... ");
};


sub add_plottool {
  my ($self, $fit) = @_;

  my $box      = Wx::StaticBox->new($self->{plottool}, -1, $fit->name, wxDefaultPosition, wxDefaultSize);
  my $boxsizer = Wx::StaticBoxSizer->new( $box, wxHORIZONTAL );

  foreach my $d (@{$fit->data}) {
    my $key = join('.', $fit->group, $d->group);
    $self->{$key} = Wx::Button->new($self->{plottool}, -1, $d->name);
    $boxsizer -> Add($self->{$key}, 0, wxALL, 5);
    EVT_BUTTON($self, $self->{$key},  sub{$self->transfer($fit, $d)});
    $self-> mouseover($key, "Put the fit to \"" . $d->name . "\" from \"" . $fit->name . "\" in the plotting list.");
  };

  $self->{scrollbox} -> Add($boxsizer, 0, wxGROW|wxALL, 5);
  $self->{plottool} -> SetSizerAndFit($self->{scrollbox});
};

## need to check if it is already in the plot list...
sub transfer {
  my ($self, $fit, $data) = @_;
  my $plotlist  = $Demeter::UI::Artemis::frames{Plot}->{plotlist};
  $plotlist->Append("Fit to " . $data->name . " from ".$fit->name, $data);
  my $i = $plotlist->GetCount - 1;
  ##$plotlist->SetClientData($i, $data);
  $plotlist->Check($i,1);
  $self->status("\"" . $data->name . "\" from \"" . $fit->name . "\" was added to the plotting list.")
};




1;


=head1 NAME

Demeter::UI::Artemis::History - A fit history interface for Artemis

=head1 VERSION

This documentation refers to Demeter version 0.4.

=head1 SYNOPSIS

Examine past fits contained in the fitting project.

=head1 CONFIGURATION


=head1 DEPENDENCIES

Demeter's dependencies are in the F<Bundle/DemeterBundle.pm> file.

=head1 BUGS AND LIMITATIONS

=over 4

=item *

Discard one or more fits, completely removing them from the project
and the order file.  Delete folder, remove from order file/hash

=item *

Export selected fit to a project file.  This contains the model of the
selected fit without the history.  Useful for bug reports and other
communications.

=item *

Calculations on the report tab: average, Einstein

=back

Please report problems to Bruce Ravel (bravel AT bnl DOT gov)

Patches are welcome.

=head1 AUTHOR

Bruce Ravel (bravel AT bnl DOT gov)

L<http://cars9.uchicago.edu/~ravel/software/>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006-2011 Bruce Ravel (bravel AT bnl DOT gov). All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlgpl>.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut