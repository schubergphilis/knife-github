require 'termios'

module Github
  class Password < String

    # Turn local terminal echo on or off. This method is used for securing the
    # display, so that a soon to be entered password will not be echoed to the
    # screen. It is also used for restoring the display afterwards.
    #
    # If _masked_ is +true+, the keyboard is put into unbuffered mode, allowing
    # the retrieval of characters one at a time. _masked_ has no effect when
    # _on_ is +false+. You are unlikely to need this method in the course of
    # normal operations.
    #
    def Password.echo(on=true, masked=false)
      term = Termios::getattr( $stdin )
  
      if on
        term.c_lflag |= ( Termios::ECHO | Termios::ICANON )
      else # off
        term.c_lflag &= ~Termios::ECHO
        term.c_lflag &= ~Termios::ICANON if masked
      end
  
      Termios::setattr( $stdin, Termios::TCSANOW, term )
    end
  
  
    # Get a password from _STDIN_, using buffered line input and displaying
    # _message_ as the prompt. No output will appear while the password is being
    # typed. Hitting <b>[Enter]</b> completes password entry. If _STDIN_ is not
    # connected to a tty, no prompt will be displayed.
    #
    def Password.get(message="Password: ")
      begin
        if $stdin.tty?
  	Password.echo false
  	print message if message
        end
  
        pw = Password.new( $stdin.gets || "" )
        pw.chomp!
  
      ensure
        if $stdin.tty?
  	Password.echo true
  	print "\n"
        end
      end
    end
  
  
    # Get a password from _STDIN_ in unbuffered mode, i.e. one key at a time.
    # _message_ will be displayed as the prompt and each key press with echo
    # _mask_ to the terminal. There is no need to hit <b>[Enter]</b> at the end.
    #
    def Password.getc(message="Password: ", mask='*')
      # Save current buffering mode
      buffering = $stdout.sync
  
      # Turn off buffering
      $stdout.sync = true
  
      begin
        Password.echo(false, true)
        print message if message
        pw = ""
  
        while ( char = $stdin.getc ) != 10 # break after [Enter]
  	putc mask
  	pw << char
        end
  
      ensure
        Password.echo true
        print "\n"
      end
  
      # Restore original buffering mode
      $stdout.sync = buffering
  
      Password.new( pw )
    end
  end
end
