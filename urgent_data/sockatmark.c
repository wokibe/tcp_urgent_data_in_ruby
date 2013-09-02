/* 
# Ruby C-extension to call ioctl with SIOCATMARK
# file: sockatmark.c

# usage:
#   require_relative 'sockatmark'
#   ...
#   atm = AtMark.new
#   ...
#   # in case of oob data
#   test = atm.atmakr(socket.fileno) 
#   # returns 1 if the urgent points is at the oob character
#   # otherwise 0 

# installation: 
#   ruby exconf.rb
#   make
*/

#include "ruby.h"
#include "stdio.h"
#include "sys/ioctl.h"
#include "sys/socket.h"

static VALUE t_atmark(VALUE self, VALUE fnum)
{
  int fd;
  int flag;
  int result;

  fd = NUM2INT(fnum);
  // printf("fd: %d\n", fd);

  result = ioctl(fd, SIOCATMARK, &flag);
  // printf("rs: %d\n", result);

  if (result < 0)
    return(-1);
    
  // printf("flag: %d\n", flag);
  return INT2NUM(flag);
}

VALUE cAtMark;

void Init_sockatmark()
{
  cAtMark = rb_define_class("AtMark", rb_cObject);
  rb_define_method(cAtMark, "atmark", t_atmark, 1);
}
