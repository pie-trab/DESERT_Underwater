#include "hdr-uwal.h"
#include "phymac-clmsg.h"
#include "uwconnector.h"
#include "uwmodem.h"
#include "uwsocket.h"
#include <arpa/inet.h>
#include <cstring>
#include <functional>
#include <mphy_pktheader.h>
#include <mutex>
#include <netinet/in.h>
#include <packet.h>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <thread>
#include <uwmulticastmodem.h>


const std::chrono::milliseconds UwMulticastModem::MODEM_TIMEOUT =
		std::chrono::milliseconds(3000);

/**
 * Class to create the Otcl shadow object for an object of the class
 * UwMulticastModem.
 */
static class UwMulticastModem_TclClass : public TclClass
{

public:
	UwMulticastModem_TclClass()
		: TclClass("Module/UW/UwModem/MULTICAST")
	{
	}

	TclObject *
	create(int, const char *const *)
	{
		return (new UwMulticastModem());
	}

} class_multicastmodem;

UwMulticastModem::UwMulticastModem()
	: UwModem()
	// TODO add modem_connector initialization
	, data_connector(new UwSocket())
	, data_address()
	, status(ModemState::AVAILABLE)
	, tx_queue_m()
	, status_cv()
	, tx_queue_cv()
	, receiving(false)
	, transmitting(false)
	, tx_thread()
	, rx_thread()
	, rx_payload("")
	, bitrate_(30000)
	, message_size(40) // bytes
	, tx_overhead_()
{
	DATA_BUFFER_LEN = 4096;
	MAX_READ_BYTES = 4096;

	data_connector->setMulticast();
	data_connector->setUDP();


	bind("bitrate", (double *) &bitrate_);
	bind("tx_overhead", (double *) &tx_overhead_);
}

UwMulticastModem::~UwMulticastModem()
{
	stop();
}

void
UwMulticastModem::recv(Packet *p)
{
	hdr_cmn *ch = HDR_CMN(p);
	hdr_MPhy *ph = HDR_MPHY(p);

	if (ch->direction() == hdr_cmn::UP) {
		if (isOn) { // is physical layer on or off
			startRx(p);
			endRx(p);
		} else {
			Packet::free(p);
		}
	} else {
		if (!isOn) {
			return;
		}
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
		ph->dstAntenna = 0;
		ph->modulationType = getModulationType(p);
		ph->duration = getTxDuration(p);

		std::unique_lock<std::mutex> tx_lock(tx_queue_m);
		tx_queue.push(p);
		tx_lock.unlock();
		printOnLog(
				LogLevel::DEBUG, "MULTICASTMODEM", "recv::PUSHING_IN_TX_QUEUE");
		tx_queue_cv.notify_one();
	}
	return;
}

int
UwMulticastModem::command(int argc, const char *const *argv)
{
	if (argc == 3) {
		if (!strcmp(argv[1], "setDataAddress")) {
			data_address = argv[2];
			return TCL_OK;
		}
		// TODO REMOVE this was the old, wrong, logic for multicast address
		// if (!strcmp(argv[1], "setMulticastAddress")) {
		// 	auto *socket = dynamic_cast<UwSocket *>(data_connector.get());
		// 	if (socket == nullptr) {
		// 		fprintf(stderr,
		// 				"Invalid connector type, multicast address requires "
		// 				"SOCKET\n");
		// 		return TCL_ERROR;
		// 	}

		// 	socket->setMulticast();
		// 	return TCL_OK;
		// }
		// TODO check if needs removing, the socket is already initialized
		// if (!strcmp(argv[1], "setConnector")) {
		// 	if (!strcmp(argv[2], "SOCKET")) {
		// 		data_connector.reset(new UwSocket());
		// 		return TCL_OK;
		// 	}
		// 	fprintf(stderr, "Invalid connector type, only SOCKET is supported");
		// 	return TCL_ERROR;
		// }
	}

	return UwModem::command(argc, argv);
}

int
UwMulticastModem::getModulationType(Packet *p)
{
	return 0;
}

double
UwMulticastModem::getTxDuration(Packet *p)
{
	if (bitrate_ <= 0) {
		return -1.0;
	}

	hdr_uwal *uwalh = HDR_UWAL(p);
	return tx_overhead_ +
			(8.0 * static_cast<double>(uwalh->binPktLength())) / bitrate_;
}

int
UwMulticastModem::recvSyncClMsg(ClMessage *m)
{
	if (m->type() == CLMSG_MAC2PHY_GETTXDURATION) {
		Packet *p = ((ClMsgMac2PhyGetTxDuration *) m)->pkt;
		hdr_cmn *ch = HDR_CMN(p);

		if (ch->direction() == hdr_cmn::DOWN) {
			double duration = getTxDuration(p);

			if (duration > 0)
				printOnLog(LogLevel::INFO,
						"MODAMODEM",
						"recvSyncClMsg::GET_TXDURATION " +
								std::to_string(duration));

			((ClMsgMac2PhyGetTxDuration *) m)->setDuration(duration);

			return 0;
		}

		// Don't set TX duration on RX.
		((ClMsgMac2PhyGetTxDuration *) m)->setDuration(-1);

		return 1;
	}

	return MPhy::recvSyncClMsg(m);
}

void
UwMulticastModem::start()
{
	printOnLog(LogLevel::DEBUG, "MULTICAST", "STARTING_DRIVER");

	// TODO, open connection to control modem parameters
	// if (!signal_conn->openConnection(signal_address)){
	// }
	// TODO the address in this case must be only port or inet_addr with port in
	// the format XXX.XXX.XXX.XXX:PORT, if it is only inet_addr without port
	// this will break. Pretty sure need to check
	if (!data_connector->openConnection(data_address)) {
		std::string err_msg =
				"FAILED_TO_OPEN_CONNECTION_AT_BROADCAST_ADDRESS_AND_PORT:" +
				data_address;
	}

	receiving.store(true);
	transmitting.store(false);

	// TODO, receiving configuration data(?) to understand if necessary in
	// multicast configuration_thread =
	// std::thread(&UwMulticastModem::receivingConfiguration, this);
	tx_thread = std::thread(&UwMulticastModem::transmittingData, this);
	rx_thread = std::thread(&UwMulticastModem::receivingData, this);

	checkTimer = new CheckTimer(this);
	checkTimer->resched(period);
}

void
UwMulticastModem::stop()
{
	receiving.store(false);
	transmitting.store(false);

	status_cv.notify_all();
	tx_queue_cv.notify_all();

	if (tx_thread.joinable())
		tx_thread.join();

	// if (p_configuration_connector->isConnected() &&
	// 		!p_configuration_connector->closeConnection())
	// 	printOnLog(LogLevel::ERROR,
	// 			"MULTICASTMODEM",
	// 			"CONFIGURATION_CONNECTION_UNABLE_TO_CLOSE");

	if (data_connector->isConnected() && !data_connector->closeConnection())
		printOnLog(LogLevel::ERROR,
				"MULTICASTMODEM",
				"DATA_CONNECTION_UNABLE_TO_CLOSE");

	// if(configuration_thread.joinable())
	// 	configuration_thread.join();
	if (tx_thread.joinable())
		tx_thread.join();
	if (rx_thread.joinable())
		rx_thread.join();

	checkTimer->force_cancel();
}

void
UwMulticastModem::receivingData()
{
	data_buffer.reserve(DATA_BUFFER_LEN);
	std::fill(data_buffer.begin(), data_buffer.end(), '\0');

	while (receiving.load()) {
		std::unique_lock<std::mutex> state_lock(status_m);
		if (status_cv.wait_for(state_lock, MODEM_TIMEOUT, [&] {
				return status == ModemState::RECEIVING;
			})) {
			state_lock.unlock();

			auto beg_it = data_buffer.begin();
			int r_bytes =
					data_connector->readFromDevice(&(*beg_it), MAX_READ_BYTES);

			if (r_bytes > 0) {
				// TODO in this condition, who assures me that the read bytes
				// will be always >= to the message size? I mean if the read
				// message is smaller that the max size it will loop forever? in
				// the code i took this from message_size was set in a specific
				// method, but is not updated here so the problem could still
				// present itself
				while (r_bytes < message_size) { // message_size to define
					r_bytes += data_connector->readFromDevice(
							&(*beg_it), MAX_READ_BYTES - r_bytes);
				}

				rx_payload = std::string(beg_it, beg_it + r_bytes);
				printOnLog(LogLevel::DEBUG,
						"MULTICASTMODEM",
						"receivingData::LEN::" +
								std::to_string(rx_payload.size()) +
								"::DATA::" + rx_payload);

				Packet *p = Packet::alloc();
				createRxPacket(p);
				std::function<void(UwModem &, Packet * p)> callback =
						&UwModem::recv;
				ModemEvent e = {callback, p};
				event_q.push(e);

				data_buffer.clear();
			}

			state_lock.lock();
			status = ModemState::AVAILABLE;
		}
	}
}

void
UwMulticastModem::createRxPacket(Packet *p)
{
	hdr_uwal *uwalh = HDR_UWAL(p);
	uwalh->binPktLength() = rx_payload.size();
	std::memset(uwalh->binPkt(), 0, uwalh->binPktLength());
	std::copy(rx_payload.begin(), rx_payload.end(), uwalh->binPkt());
	HDR_CMN(p)->direction() = hdr_cmn::UP;
}

void
UwMulticastModem::transmittingData()
{
	while (transmitting.load()) {
		std::unique_lock<std::mutex> tx_lock(tx_queue_m);

		tx_queue_cv.wait(
				tx_lock, [&] { return !tx_queue.empty() || !transmitting; });

		if (!transmitting.load())
			break;

		Packet *pck = tx_queue.front();
		tx_queue.pop();
		tx_lock.unlock();
		if (pck) {
			startTx(pck);
		}

		printOnLog(LogLevel::DEBUG,
				"MULTICASTMODEM",
				"transmittingData::BLOCKING_ON_NEXT_PACKET");
	}
}

void
UwMulticastModem::startTx(Packet *p)
{
	hdr_uwal *uwalh = HDR_UWAL(p);
	std::string payload;
	payload.assign(uwalh->binPkt(), uwalh->binPktLength());

	std::unique_lock<std::mutex> state_lock(status_m);
	if (status_cv.wait_for(state_lock, MODEM_TIMEOUT, [&] {
			return status == ModemState::AVAILABLE;
		})) {
		status = ModemState::TRANSMITTING;
		state_lock.unlock();

		if ((data_connector->writeToDevice(payload)) < 0) {
			printOnLog(LogLevel::ERROR,
					"MULTICASTMODEM",
					"startTx::FAIL_TO_WRITE_DATA_TO_DEVICE");
			return;
		}

		std::function<void(UwModem &, Packet * p)> callback =
				&UwModem::realTxEnded;
		ModemEvent e = {callback, p};
		event_q.push(e);

		printOnLog(
				LogLevel::INFO, "MULTICASTMODEM", "startTx::PAKCET_TRANSMITTED");
	}
}

void
UwMulticastModem::completeTx(Packet *p, bool success)
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
UwMulticastModem::startRx(Packet *p)
{
	printOnLog(
			LogLevel::INFO, "MULTICASTMODEM", "startRx::CALL_PHY2MACSTARTRX");
	Phy2MacStartRx(p);
}

void
UwMulticastModem::endRx(Packet *p)
{
	printOnLog(LogLevel::INFO, "MULTICASTMODEM", "endRx::CALL_SENDUP");
	sendUp(p, 0.01);
}

bool
UwMulticastModem::configure()
{
	return false;
}
