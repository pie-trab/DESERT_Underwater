#include "uwlumaxmodem.h"

#include "phymac-clmsg.h"

#include <chrono>
#include <thread>
#include <uwsocket.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <functional>
#include <iostream>
#include <string>

const std::chrono::milliseconds UwLumaXModem::MODEM_TIMEOUT =
		std::chrono::milliseconds(3000);

/**
 * Class to create the OTcl shadow object for an UwLumaXModem object.
 */
static class UwLumaXModem_TclClass : public TclClass
{
public:
	UwLumaXModem_TclClass()
		: TclClass("Module/UW/UwModem/LumaX")
	{
	}

	TclObject *
	create(int args, const char *const *argv)
	{
		return (new UwLumaXModem());
	}
} class_lumaxmodem;

UwLumaXModem::UwLumaXModem()
	: UwModem()
	, p_connector(new UwSocket())
	, p_interpreter(new UwInterpreterLumaX())
	, status(ModemState::AVAILABLE)
	, status_m()
	, tx_queue_m()
	, status_cv()
	, tx_queue_cv()
	, receiving(false)
	, transmitting(false)
	, rx_thread()
	, tx_thread()
	, rx_payload("")
	, bitrate_(0.0)
	, tx_overhead_(0.0)
{
	DATA_BUFFER_LEN = 4096;
	MAX_READ_BYTES = 4096;

	bind("bitrate", (double *) &bitrate_);
	bind("tx_overhead", (double *) &tx_overhead_);
}

UwLumaXModem::~UwLumaXModem()
{
	stop();
}

void
UwLumaXModem::start()
{
	if (modem_address == "") {
		std::cout << "ERROR: Modem address not set!" << std::endl;
		printOnLog(LogLevel::ERROR, "LUMAXMODEM", "start::ADDRESS_NOT_SET");
		return;
	}

	if (DATA_BUFFER_LEN == 0) {
		DATA_BUFFER_LEN = 4096;
	}
	if (MAX_READ_BYTES <= 0) {
		MAX_READ_BYTES = DATA_BUFFER_LEN;
	}

	printOnLog(LogLevel::DEBUG, "LUMAXMODEM", "start::OPEN_CONNECTION");

	if (!p_connector->openConnection(modem_address)) {
		std::cout << "ERROR: connection to modem failed to open: "
				  << modem_address << std::endl;
		printOnLog(
				LogLevel::ERROR, "LUMAXMODEM", "start::CONNECTION_OPEN_FAILED");
		return;
	}

	receiving.store(true);
	transmitting.store(true);

	rx_thread = std::thread(&UwLumaXModem::receivingData, this);
	tx_thread = std::thread(&UwLumaXModem::transmittingData, this);

	if (checkTimer == NULL) {
		checkTimer = new CheckTimer(this);
	}
	checkTimer->resched(period);
}

void
UwLumaXModem::recv(Packet *p)
{
	hdr_cmn *ch = HDR_CMN(p);
	hdr_MPhy *ph = HDR_MPHY(p);

	if (ch->direction() == hdr_cmn::UP) { // UP
		if (isOn) {
			startRx(p);
			endRx(p);
		} else {
			Packet::free(p);
		}
		return;
	}

	if (!isOn) {
		return;
	}

	// DOWN
	ph->Pr = 0;
	ph->Pn = 0;
	ph->Pi = 0;
	ph->txtime = NOW;
	ph->rxtime = ph->txtime;

	ph->worth_tracing = false;

	ph->srcSpectralMask = getTxSpectralMask(p);
	ph->srcAntenna = getTxAntenna(p);
	ph->srcPosition = getPosition();
	ph->dstSpectralMask = 0;
	ph->dstPosition = 0;
	ph->dstAntenna = 0;
	ph->modulationType = getModulationType(p);
	ph->duration = getTxDuration(p);

	std::unique_lock<std::mutex> tx_lock(tx_queue_m);
	tx_queue.push(p);
	tx_lock.unlock();
	tx_queue_cv.notify_one();

	printOnLog(LogLevel::DEBUG, "LUMAXMODEM", "recv::PUSHING_IN_TX_QUEUE");
}

int
UwLumaXModem::command(int argc, const char *const *argv)
{
	if (argc == 2) {
		if (!strcmp(argv[1], "setTCP")) {
			p_connector->setTCP();
			return TCL_OK;
		}
		if (!strcmp(argv[1], "setUDP")) {
			p_connector->setUDP();
			return TCL_OK;
		}
		if (!strcmp(argv[1], "setServer")) {
			p_connector->setServer();
			return TCL_OK;
		}
	} else if (argc == 3) {
		if (!strcmp(argv[1], "setConnector")) {
			if (!strcmp(argv[2], "SOCKET")) {
				p_connector.reset(new UwSocket());
				return TCL_OK;
			}
			fprintf(stderr, "Invalid connector type, only SOCKET is supported");
			return TCL_ERROR;
		}
	}

	return UwModem::command(argc, argv);
}

int
UwLumaXModem::recvSyncClMsg(ClMessage *m)
{
	if (m->type() == CLMSG_MAC2PHY_GETTXDURATION) {
		Packet *p = ((ClMsgMac2PhyGetTxDuration *) m)->pkt;
		hdr_cmn *ch = HDR_CMN(p);

		if (ch->direction() == hdr_cmn::DOWN) {
			double duration = getTxDuration(p);
			((ClMsgMac2PhyGetTxDuration *) m)->setDuration(duration);
			return duration > 0 ? 0 : 1;
		}

		((ClMsgMac2PhyGetTxDuration *) m)->setDuration(-1);
		return 1;
	}

	return MPhy::recvSyncClMsg(m);
}

double
UwLumaXModem::getTxDuration(Packet *p)
{
	if (bitrate_ <= 0) {
		return -1.0;
	}

	hdr_uwal *uwalh = HDR_UWAL(p);
	return tx_overhead_ +
			(8.0 * static_cast<double>(uwalh->binPktLength())) / bitrate_;
}

void
UwLumaXModem::stop()
{
	receiving.store(false);
	transmitting.store(false);

	status_cv.notify_all();
	tx_queue_cv.notify_all();

	if (tx_thread.joinable()) {
		tx_thread.join();
	}

	if (p_connector->isConnected() && !p_connector->closeConnection()) {
		printOnLog(
				LogLevel::ERROR, "LUMAXMODEM", "stop::CONNECTION_CLOSE_FAIL");
	}

	if (rx_thread.joinable()) {
		rx_thread.join();
	}

	if (checkTimer != NULL) {
		checkTimer->force_cancel();
		delete checkTimer;
		checkTimer = NULL;
	}
}

void
UwLumaXModem::transmittingData()
{
	while (transmitting.load()) {
		std::unique_lock<std::mutex> tx_lock(tx_queue_m);
		tx_queue_cv.wait(tx_lock,
				[&] { return !tx_queue.empty() || !transmitting.load(); });
		if (!transmitting.load()) {
			break;
		}

		Packet *pck = tx_queue.front();
		tx_queue.pop();
		tx_lock.unlock();

		if (pck) {
			startTx(pck);
		}

		printOnLog(LogLevel::DEBUG,
				"LUMAXMODEM",
				"transmittingData::BLOCKING_ON_NEXT_PACKET");
	}
}

void
UwLumaXModem::receivingData()
{
	data_buffer.resize(DATA_BUFFER_LEN);
	std::fill(data_buffer.begin(), data_buffer.end(), '\0');

	const int read_size =
			std::min(MAX_READ_BYTES, static_cast<int>(DATA_BUFFER_LEN));

	while (receiving.load()) {
		// Transparent mode assumes one connector read maps to one modem
		// payload. Add framing in UwInterpreterLumaX if the socket becomes a
		// byte stream.
		int r_bytes =
				p_connector->readFromDevice(data_buffer.data(), read_size);

		if (r_bytes <= 0) {
			if (receiving.load()) {
				printOnLog(LogLevel::ERROR,
						"LUMAXMODEM",
						"receivingData::READ_FAILED_OR_CONNECTION_CLOSED");
				std::this_thread::sleep_for(std::chrono::milliseconds(100));
				continue;
			}
			break;
		}

		auto beg_it = data_buffer.begin();
		auto end_it = beg_it + r_bytes;
		auto rsp_beg = beg_it;
		auto rsp_end = beg_it;

		UwInterpreterLumaX::Response rsp =
				p_interpreter->findResponse(beg_it, end_it, rsp_beg);

		if (p_interpreter->parseResponse(
					rsp, end_it, rsp_beg, rsp_end, rx_payload)) {
			printOnLog(LogLevel::DEBUG,
					"LUMAXMODEM",
					"receivingData::RX_BYTES=" +
							std::to_string(rx_payload.size()));

			Packet *p = Packet::alloc();
			createRxPacket(p);
			std::function<void(UwModem &, Packet * p)> callback =
					&UwModem::recv;
			ModemEvent e = {callback, p};
			event_q.push(e);
		}

		std::fill(data_buffer.begin(), data_buffer.end(), '\0');
	}
}

void
UwLumaXModem::createRxPacket(Packet *p)
{
	hdr_uwal *uwalh = HDR_UWAL(p);
	uwalh->binPktLength() = rx_payload.size();
	std::memset(uwalh->binPkt(), 0, uwalh->binPktLength());
	std::copy(rx_payload.begin(), rx_payload.end(), uwalh->binPkt());
	HDR_CMN(p)->direction() = hdr_cmn::UP;
}

void
UwLumaXModem::completeTx(Packet *p, bool success)
{
	if (!success) {
		HDR_CMN(p)->error_ = 1;
	}

	{
		std::lock_guard<std::mutex> state_lock(status_m);
		status = ModemState::AVAILABLE;
	}
	status_cv.notify_all();

	std::function<void(UwModem &, Packet * p)> callback = &UwModem::realTxEnded;
	ModemEvent e = {callback, p};
	event_q.push(e);
}

void
UwLumaXModem::startTx(Packet *p)
{
	hdr_uwal *uwalh = HDR_UWAL(p);
	std::string payload;
	payload.assign(uwalh->binPkt(), uwalh->binPktLength());

	std::unique_lock<std::mutex> state_lock(status_m);
	if (!status_cv.wait_for(state_lock, MODEM_TIMEOUT, [&] {
			return status == ModemState::AVAILABLE;
		})) {
		printOnLog(LogLevel::ERROR,
				"LUMAXMODEM",
				"startTx::TIMEOUT_WAITING_FOR_AVAILABLE");
		state_lock.unlock();
		completeTx(p, false);
		return;
	}

	status = ModemState::TRANSMITTING;
	state_lock.unlock();

	int written = p_connector->writeToDevice(payload);
	bool success =
			payload.empty() || written >= static_cast<int>(payload.size());

	if (!success) {
		printOnLog(LogLevel::ERROR,
				"LUMAXMODEM",
				"startTx::FAIL_TO_WRITE_TO_DEVICE");
	} else {
		printOnLog(LogLevel::INFO,
				"LUMAXMODEM",
				"startTx::PACKET_WRITTEN_BYTES=" + std::to_string(written));
	}

	completeTx(p, success);
}

void
UwLumaXModem::startRx(Packet *p)
{
	printOnLog(LogLevel::INFO, "LUMAXMODEM", "startRx::CALL_PHY2MACSTARTRX");
	Phy2MacStartRx(p);
}

void
UwLumaXModem::endRx(Packet *p)
{
	printOnLog(LogLevel::INFO, "LUMAXMODEM", "endRx::CALL_SENDUP");
	sendUp(p, 0.01);
}
