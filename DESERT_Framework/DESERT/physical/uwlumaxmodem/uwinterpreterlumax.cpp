#include "uwinterpreterlumax.h"

UwInterpreterLumaX::Response
UwInterpreterLumaX::findResponse(std::vector<char>::iterator beg,
		std::vector<char>::iterator end, std::vector<char>::iterator &rsp)
{
	if (beg == end) {
		return Response::NO_COMMAND;
	}

	rsp = beg;
	return Response::DATA;
}

bool
UwInterpreterLumaX::parseResponse(Response rsp, std::vector<char>::iterator end,
		std::vector<char>::iterator rsp_beg,
		std::vector<char>::iterator &rsp_end, std::string &rx_payload)
{
	if (rsp != Response::DATA || rsp_beg == end) {
		return false;
	}

	rsp_end = end;
	rx_payload.assign(rsp_beg, rsp_end);
	return true;
}
