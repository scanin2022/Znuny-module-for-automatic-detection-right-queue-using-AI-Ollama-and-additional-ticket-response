#!/usr/bin/perl
# Module write by Anton/Ilya Muravyev Russia, scanin[@]mail[.]ru
# Module Licensed by GPLv3 (GNU General Public License Version 3) 
# For Free use

#package Custom::Kernel::Modules::OllamaQueueRouter;
package OllamaQueueRouter;


use strict;
use warnings;
use JSON::XS;
use JSON::MaybeXS;
use HTTP::Tiny;
use Encode qw(encode_utf8 decode_utf8);

sub new {
    my ( $Type, %Param ) = @_;
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

# Main metod auto call from Znuny
sub Run {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $TicketID = $Param{TicketID};
    my $UserID   = $Param{UserID};

    # Take objects from ObjectManager
    my $OM = $Kernel::OM;
    my $TicketObject = $OM->Get('Kernel::System::Ticket');
    my $ArticleObject = $OM->Get('Kernel::System::Ticket::Article');


    # Take Ticket data
    my %Ticket = $TicketObject->TicketGet(
        TicketID => $TicketID,
        UserID   => 1,
    );
    if ( !%Ticket ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Ticket $TicketID not found.",
        );
        return 0;
    }

    # Take First Article Tiket data
    my @Articles = $ArticleObject->ArticleList(
        TicketID => $TicketID,
  	    SenderType => 'customer',
	    OnlyFirst => 1
    );

    if ( !@Articles ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "No articles in ticket $TicketID.",
        );
        return 0;
    }

    my $ArticleBackendObject = $ArticleObject->BackendForArticle( %{$Articles[0]} );
    my %Article = $ArticleBackendObject->ArticleGet( %{$Articles[0]} );

    my $Body = $Article{Body} || '';
    my $Subject = $Article{Subject} || '';

    # Sending first question to Ollama (choosing the right queue for a ticket)
    my $OllamaResponse = $Self->_CallOllama(
        Subject => $Subject,
        Body    => $Body,
    );

    if ( !$OllamaResponse->{success} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Ollama call failed for ticket $TicketID.",
        );
        return 0;
    }

    # Parse answer from Ollama: wait ID queue or set default
    my $TargetQueueID;
    eval {
        my $data = $OllamaResponse;
        $TargetQueueID = $data->{queue} || 12;                           # default departmanet
    };

#    $LogObject->Log(
#        Priority => 'error',
#        Message  => "Ollama debug 2: $TargetQueueID",
#    );

#    if ( $@ || !$TargetQueueID || $TargetQueueID !~ /^\d+$/ ) {
#        $LogObject->Log(
#            Priority => 'error',
#            Message  => "Invalid queue_id from Ollama: '$TargetQueueID' for ticket $TicketID.",
#        );
#        return 0;
#   }

    # Set new queue to ticket
    my $Success = $TicketObject->TicketQueueSet(
        TicketID  => $TicketID,
        QueueID   => $TargetQueueID,
        UserID   => 1,
    );

    if ( !$Success ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Failed to set queue $TargetQueueID for ticket $TicketID.",
        );
        return 0;
    }

    # Sending to Ollama second question, about additional help, wait text answer
    my $OllamaResponse2 = $Self->_CallOllama2(
        Subject => $Subject,
        Body    => $Body,
    );

    if ( !$OllamaResponse2->{success} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Ollama second call failed for ticket $TicketID.",
        );
        return 0;
    }

    my $data2 = $OllamaResponse2;
    my $HelpString = $data2->{queue};


    if ( $@ || !$HelpString ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "Invalid queue_id from Ollama: '$HelpString' for ticket $TicketID.",
        );
        return 0;
    }

    my $Bodyfill = "LLM set queue: " . $TargetQueueID . "\n";
    $Bodyfill = Encode::decode("utf8", $Bodyfill);

    $Bodyfill = $Bodyfill . $HelpString;

    my $Subject_my = "Automatic queue assignment using LLM and provision of a possible solution to the request";
    $Subject_my = Encode::decode("utf8", $Subject_my);


    # Adding Article with right queue (answer from Ollama)
    $ArticleObject->ArticleCreate(
        TicketID          => $TicketID,
        ArticleType        => 'note-internal',
        SenderType         => 'system',
        From               => 'Ollama Router',
 	    Subject		 => $Subject_my,
#        ContentType        => 'text/plain',
        ContentType    => 'text/plain; charset=utf-8',
#        Charset            => 'UTF-8',
        HistoryType        => 'AddNote',
        HistoryComment      => "Queue decision by Ollama",
        Body               => $Bodyfill,
#        UserID             => $UserID,
        UserID   => 1,
	    ChannelName    => 'Internal',
        IsVisibleForCustomer => 'VisibleForCustomer',
    );

    $LogObject->Log(
        Priority => 'info',
        Message  => "Ticket $TicketID routed to queue $TargetQueueID via Ollama.",
    );

    return 1;
}

# First Call API Ollama
sub _CallOllama {
    my ( $Self, %Param ) = @_;

    my $Subject = $Param{Subject} || '';
    my $Body    = $Param{Body}    || '';

    my $URL = 'http://XXX.XXX.XXX.XXX:11434/api/generate';   # Set your ip address of Ollama server

    my $Payload = {
        model  => 'second_constantine/yandex-gpt-5-lite:8b',
        prompt => <<"END_PROMPT",
You act as a request handler for employee requests to the technical support service. It has the following department numbers:
11 - User support for support and maintenance of user workstations, their PCs, software installed on PCs, and peripheral equipment connected to their PCs;
17 - User support for the Krasnodarelectroset branch for support and maintenance of user workstations, their PCs, software installed on PCs, and peripheral equipment connected to their PCs;
15 - Telephone system support, any requests related to telephony, voice communications, and voice selectors;
6 - Support and maintenance of server infrastructure and data storage, basic infrastructure services: AD, DNS, DCHP, NTP, file servers, physical and virtual servers, virtualization clusters, and mail servers;
9 - Support and maintenance of data networks, switches, routers, and private networks. Connecting user network devices is not their responsibility.
16 - Website maintenance and customer personal account servicing;
10 - Information security services: antivirus systems, communication channel protection and encryption systems, external device monitoring, VIPN access approval, account management;
13 - GIS and Gorset software maintenance;
14 - Maintenance and servicing of automated intelligent commercial electricity metering systems;
7 - Maintenance of 1C software configurations, except for 1C ADEK and 1C ERP;
8 - Maintenance of 1C ADEK and 1C ERP.
Based on the employee's message below, determine which department to send the request to. If the answer is unclear, forward it to department number 12. Please provide only the department number listed above.

Subject: $Subject
Text: $Body

Answer:
END_PROMPT
        stream => \0,
    };

    my $HTTP = HTTP::Tiny->new( timeout => 600 );
    my $Result = $HTTP->post(
        $URL,
        {
            content => encode_json($Payload),
            headers => { 'Content-Type' => 'application/json'}, #, 'charset' => 'utf-8' },
        }
    );

    if ( !$Result->{success} ) {
        return { success => 0, error => 'HTTP error' };
    }

    my $Data = decode_json( $Result->{content} );

    my $ResponseText = $Data->{response};               # default department
#    $ResponseText =~ s/\s+//g;                         # clear special chars

    my $Queue = 12;                                     # default department

    if($ResponseText == 7) {                            # other department
	    $Queue = 7;
    }
    if($ResponseText == 8) {                            # other department
        $Queue = 8;
    }
    if($ResponseText == 6) {                            # other department
	    $Queue = 6;
    }
    if($ResponseText == 16) {                           # other department
	    $Queue = 16;
    }
    if($ResponseText == 17) {                           # other department
	    $Queue = 17;
    }
    if($ResponseText == 10) {                           # other department
	    $Queue = 10;
    }
    if($ResponseText == 13) {                           # other department
	    $Queue = 13;
    }
    if($ResponseText == 9) {                            # other department
	    $Queue = 9;
    }
    if($ResponseText == 15) {                           # other department
	    $Queue = 15;
    }
    if($ResponseText == 11) {                           # other department
	    $Queue = 11;
    }
    if($ResponseText == 14) {                           # other department
	    $Queue = 14;
    }

    return {
        success => 1,
        queue   => $Queue,
        reason  => "LLM result queue: '$Queue'\n",
#        thinking => $Data->{thinking},
    };
}

# Second Call API Ollama2
sub _CallOllama2 {
    my ( $Self, %Param ) = @_;

    my $Subject = $Param{Subject} || '';
    my $Body    = $Param{Body}    || '';

    my $URL = 'http://XXX.XXX.XXX.XXX:11434/api/generate';   #Set Your Ollama IP external|internal server

    my $Payload = {
        model  => 'second_constantine/yandex-gpt-5-lite:8b',
        prompt => <<"END_PROMPT",
You are an IT technical assistant. For the following employee request, please provide possible solutions. If a solution cannot be described, please indicate what information is needed to further refine the request.

Subject: $Subject
Text: $Body

Answer:
END_PROMPT
        stream => \0,
    };

    my $HTTP = HTTP::Tiny->new( timeout => 600 );
    my $Result = $HTTP->post(
        $URL,
        {
            content => encode_json($Payload),
            headers => { 'Content-Type' => 'application/json'}, #, 'charset' => 'utf-8' },
        }
    );

    if ( !$Result->{success} ) {
        return { success => 0, error => 'HTTP error' };
    }

    my $Data = decode_json( $Result->{content} );

    my $ResponseText = $Data->{response} || '\nLLM result!\n';

    return {
        success => 1,
        queue   => $ResponseText,
#        thinking => $Data->{thinking},
    };
}

1;