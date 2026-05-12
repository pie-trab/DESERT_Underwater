
#ifndef UWINTERPRETERLUMAX_H
#define UWINTERPRETERLUMAX_H

#include <cstdarg>
#include <iterator>
#include <memory>
#include <string>
#include <vector>


class UwInterpreterLumaX 
{
public:
    virtual int parse(char* buffer);
    virtual int retrievePayload(std::string message);
};

#endif