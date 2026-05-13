
#ifndef UWINTERPRETERLUMAX_H
#define UWINTERPRETERLUMAX_H

#include <string>
#include <vector>

/**
 * Minimal interpreter for LumaX transparent socket mode.
 *
 * The modem does not prepend status tokens or custom data headers in this
 * mode, so every non-empty read from the connector is treated as payload.
 * If future firmware adds framing or status messages, this is the class to
 * extend without changing the modem-driver flow.
 */
class UwInterpreterLumaX
{
public:
	enum class Response { DATA = 0, NO_COMMAND };

	UwInterpreterLumaX() = default;
	virtual ~UwInterpreterLumaX() = default;

	UwInterpreterLumaX::Response findResponse(std::vector<char>::iterator beg,
			std::vector<char>::iterator end, std::vector<char>::iterator &rsp);

	bool parseResponse(UwInterpreterLumaX::Response rsp,
			std::vector<char>::iterator end,
			std::vector<char>::iterator rsp_beg,
			std::vector<char>::iterator &rsp_end, std::string &rx_payload);
};

#endif
