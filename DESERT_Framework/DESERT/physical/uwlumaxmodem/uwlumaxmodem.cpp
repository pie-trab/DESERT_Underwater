#include "uwlumaxmodem.h"
#include "uwmodem.h"
#include <string>
#include <uwsocket.h>

UwLumaXModem::UwLumaXModem()
	: UwModem()
	, p_connector(new UwSocket())
	, p_interpreter(new UwInterpreterLumaX())
	, tx_queue_m()
{
}

void
UwLumaXModem::recv(Packet *p)
{
	hdr_cmn *ch = HDR_CMN(p);
	hdr_MPhy *ph = HDR_MPHY(p);
	if (ch->direction() == hdr_cmn::UP) {
		


	} else { // DOWN
		ph->dstSpectralMask = 0;
		ph->dstPosition = 0;
		ph->dstAntenna = 0;
		ph->modulationType = getModulationType(p);
		ph->duration = getTxDuration(p);

		std::unique_lock<std::mutex> tx_lock(tx_queue_m);
		tx_queue.push(p);
		tx_lock.unlock();
		printOnLog(LogLevel::DEBUG, "LUMAXMODEM", "recv::PUSHING_IN_TX_QUEUE");
		tx_queue_cv.notify_one();
	}
}

void
UwLumaXModem::startTx(Packet *p)
{
	hdr_mac *mach = HDR_MAC(p);
	hdr_uwal *uwalh = HDR_UWAL(p);
	std::string payload;
	payload.assign(uwalh->binPkt(), uwalh->binPktLength());

	// build a command

	// std::string send_cmd = "SENDING"; // sending command
	// uint length = payload.size(); // size of the payload
	// std::string destination = std::to_string(dest); // destination node

	// std::string cmd = send_cmd + ":" + length + ":" + payload + ":" +
	// destination;

	p_connector->openConnection(modem_address);
	p_connector->writeToDevice(payload);
}

// void
// UwLumaXModem::receivingData()
// {
// 	uint READ_BYTES;
// 	char *buffer;
// 	int n_bytes = p_connector->readFromDevice(buffer, READ_BYTES);
// 	// status_t state =
// 	int state = 1; // = interpreter->parse(buffer);

// 	switch (state)
// 	{
// 	case 0:

// 		break;
// 	default:
// 		break;
// 	}
// }

void
UwLumaXModem::startRx(Packet *p)
{
	uint READ_BYTES;
	char *buffer;
	// receive the message
	int msg_len = p_connector->readFromDevice(buffer, READ_BYTES);
	printOnLog(UwModem::LogLevel::DEBUG,
			"LUMAXMODEM",
			std::string("message received: ") + buffer);

	// parse the message to the state
	int state = p_interpreter->parse(buffer);

	switch (state) {
		// TODO implement case check
		case 0:
			break;
		case 1:
			break;
		case 2:
			break;
		case 3:
			break;
		case 4:
			break;
	}
}

void
endRx(Packet *p)
{
}
