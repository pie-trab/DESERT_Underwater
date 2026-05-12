#include "uwinterpreterlumax.h"

#include <algorithm>

int
retrievePayload(std::string message)
{
	char init_cmd; // bits or char identifying payload start
	char end_cmd; // bits or char identifying payload end
	auto it = std::search(message.begin(), message.end(), init_cmd, end_cmd);
	std::string data = std::string(it, message.end());

	return 0;
}